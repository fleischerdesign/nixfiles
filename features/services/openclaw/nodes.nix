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
      stateDir = "${account.home}/.local/share/openclaw/nodes/${node.gateway}/${node.instance}";
      host = config.my.topology.hosts.${node.gateway}.wireguardIpv4;
      port =
        systems.${node.gateway}.config.my.contracts.provides."openclaw-${node.instance}".endpoints.web.port;
      built = runtime.build {
        inherit id stateDir;
        package = cfg.package;
        runtime = node;
        settings = lib.recursiveUpdate node.settings {
          gateway = {
            mode = "remote";
            remote.url = "ws://${host}:${toString port}";
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
    systemd.tmpfiles.rules = lib.concatMap (node: [
      "d ${node.stateDir} 0700 ${user} ${account.group} - -"
    ]) nodes;
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
