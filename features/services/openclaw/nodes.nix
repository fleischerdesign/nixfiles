{
  config,
  lib,
  pkgs,
  fleetConfigs,
  ...
}:
let
  cfg = config.my.features.services.openclaw;
  runtime = import ./runtime.nix { inherit lib pkgs; };
  systems = fleetConfigs.systems config;
  user = config.my.user.primary;
  account = config.users.users.${user};
  make =
    _: node:
    let
      id = "openclaw-node-${node.gateway}-${node.instance}-${user}";
      # Node state is service state: it holds the device identity and managed worktrees, so it lives
      # under /var/lib rather than in the user's home. Putting it under `~/.local/share` lets
      # systemd-tmpfiles create parent directories as root below a user-owned tree - an ownership
      # transition it refuses as unsafe - and the working directory then never exists on a fresh
      # host. Every level below is declared here with the node's owner, so the chain is correct on
      # first boot as well as on later ones.
      stateDir = "/var/lib/openclaw-nodes/${user}/${node.gateway}/${node.instance}";
      host = config.my.topology.hosts.${node.gateway}.wireguardIpv4;
      port =
        systems.${node.gateway}.config.my.contracts.provides."openclaw-${node.instance}".endpoints.web.port;
      built = runtime.build {
        inherit id stateDir;
        package = cfg.package;
        runtime = node // {
          # The gateway rejects an internal client that authenticates with nothing; the device
          # identity is for pairing, not for login. A node therefore authenticates with the same
          # local-direct credential the gateway itself uses, named by the node and delivered as a
          # private file rather than a value in the config.
          credentialFiles =
            node.credentialFiles
            // lib.optionalAttrs (node.passwordSecret != null) {
              OPENCLAW_GATEWAY_PASSWORD = config.sops.secrets.${node.passwordSecret}.path;
            };
        };
        settings = lib.recursiveUpdate node.settings {
          gateway = {
            mode = "remote";
            remote.url = "ws://${host}:${toString port}";
          }
          // lib.optionalAttrs (node.passwordSecret != null) {
            remote.password = {
              source = "env";
              provider = "default";
              id = "OPENCLAW_GATEWAY_PASSWORD";
            };
          };
        };
      };
      command = "${built.launcher}/bin/${id} node run --host ${host} --port ${toString port} --display-name ${config.networking.hostName}";
      serviceConfig = node.serviceConfig // {
        ExecStart = command;
        WorkingDirectory = stateDir;
        Restart = "on-failure";
        RestartSec = 5;
        UMask = "0077";
      };
    in
    {
      inherit
        id
        user
        stateDir
        node
        built
        serviceConfig
        ;
      inherit (node) passwordSecret;
    };
  nodes = lib.mapAttrsToList make cfg.nodes;
in
{
  config = lib.mkIf cfg.enable {
    environment.systemPackages = lib.concatMap (node: [
      node.built.launcher
      node.built.execute
      # Exported under the name `openclaw` so a remote, non-interactive probe can run
      # `openclaw node identity --json`: the gateway's SSH-verified pairing does exactly that
      # before approving a node's first capability surface. The wrapper supplies the node's state
      # directory, so the probed identity is the node's own.
      (pkgs.writeShellScriptBin "openclaw" ''
        exec ${node.built.execute}/bin/${node.id}-exec openclaw "$@"
      '')
    ]) nodes;
    environment.etc = lib.listToAttrs (
      map (node: lib.nameValuePair "openclaw/${node.id}.json" { source = node.built.source; }) nodes
    );
    systemd.tmpfiles.rules = lib.unique (
      lib.concatMap (node: [
        "d /var/lib/openclaw-nodes 0711 root root - -"
        "d /var/lib/openclaw-nodes/${user} 0750 ${user} ${account.group} - -"
        "d ${builtins.dirOf node.stateDir} 0750 ${user} ${account.group} - -"
        "d ${node.stateDir} 0700 ${user} ${account.group} - -"
      ]) nodes
    );
    sops.secrets = lib.listToAttrs (
      lib.concatMap (
        node:
        lib.optional (node.passwordSecret != null) {
          name = node.passwordSecret;
          value = {
            owner = user;
            mode = "0400";
          };
        }
      ) nodes
    );
    systemd.services = lib.listToAttrs (
      map (
        node:
        lib.nameValuePair node.id {
          description = "OpenClaw node (${user})";
          wantedBy = [ "multi-user.target" ];
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          restartTriggers = [
            node.built.source
            node.built.launcher
          ];
          serviceConfig = node.serviceConfig // {
            User = user;
            Group = account.group;
          };
        }
      ) (lib.filter (node: !node.node.session) nodes)
    );
    my.features.services.openclaw.sessionNodes = lib.listToAttrs (
      map (
        node:
        lib.nameValuePair node.id {
          inherit user;
          Unit = {
            Description = "Personal OpenClaw node (${node.node.instance})";
            After = [ "graphical-session.target" ];
            PartOf = [ "graphical-session.target" ];
            X-Restart-Triggers = [
              "${node.built.source}"
              "${node.built.launcher}"
            ];
          };
          Service = node.serviceConfig;
          Install.WantedBy = [ "graphical-session.target" ];
        }
      ) (lib.filter (node: node.node.session) nodes)
    );
  };
}
