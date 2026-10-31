# The Paseo daemon: one per machine, owning that machine's agents, workspaces and schedules.
#
# Peers are not configured here. A host that enables the daemon is a peer of every other one, and
# the address and port come from that peer's own evaluated configuration - the fleet decides the
# mesh once, in `inventory/hosts.nix`, and this module reads it instead of repeating it.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.my.features.dev.paseo.daemon;
  hostName = config.networking.hostName;
  system = pkgs.stdenv.hostPlatform.system;
  fleetConfigs = import ../../../../lib/fleet-configs.nix { inherit lib; };
  systems = fleetConfigs.systems config;
  peers = lib.filterAttrs (
    name: host: name != hostName && (host.config.my.features.dev.paseo.daemon.enable or false)
  ) systems;
  plugins = (import ../plugins.nix { inherit lib; }).findPlugins ../plugins;
  paseo = "${cfg.package}/bin/paseo";
  quote = lib.escapeShellArg;
  daemonEnv = {
    PASEO_HOME = cfg.stateDir;
    HOME = cfg.stateDir;
    PASEO_LISTEN = "${cfg.listenAddress}:${toString cfg.port}";
    PASEO_RELAY_ENABLED = lib.boolToString cfg.relay;
  };

  # Peers, Hub enrollment and plugins are runtime state in `$PASEO_HOME`, because the daemon owns
  # those files. The unit reconciles them on every boot instead of writing them: a repeated
  # registration of an unchanged host returns the saved entry, so the pass is a no-op unless the
  # fleet, the plugin list or the credential changed.
  #
  # The script is a derivation rather than a systemd `script` block so shellcheck and `set -euo
  # pipefail` apply to it, and so a broken invocation fails the build instead of a host.
  configure = pkgs.writeShellApplication {
    name = "paseo-configure";
    runtimeInputs = [ cfg.package ];
    text = ''
      # The unit starts after the daemon, not when it is ready to answer. `daemon status` only
      # proves a PID exists; an RPC does, so the wait is a real request rather than a liveness
      # check - a daemon still loading plugins accepts the process but refuses work.
      ready=0
      for _ in {1..60}; do
        if paseo --home ${quote cfg.stateDir} host ls >/dev/null 2>&1; then
          ready=1
          break
        fi
        sleep 2
      done
      if [ "$ready" -eq 0 ]; then
        echo "paseo: daemon did not answer within 120s" >&2
        exit 1
      fi

      ${
        if cfg.connectPeers then
          lib.concatMapStringsSep "\n" (
            peer:
            let
              peerCfg = systems.${peer}.config.my.features.dev.paseo.daemon;
              address = systems.${peer}.config.my.topology.hosts.${peer}.wireguardIpv4;
            in
            "paseo --home ${quote cfg.stateDir} host add ${quote "tcp://${address}:${toString peerCfg.port}"} --label ${quote peer}"
          ) (lib.attrNames peers)
        else
          ": peer registration disabled"
      }

      ${lib.optionalString cfg.hub.enable ''
        # The key travels in the environment, not in argv: a command line is world-readable in
        # the process list.
        PASEO_HUB_API_KEY="$(< ${quote config.sops.secrets.${cfg.hub.apiKeySecret}.path})" \
          paseo --home ${quote cfg.stateDir} hub connect ${quote cfg.hub.origin} \
          ${lib.concatMapStringsSep " " (
            permission: "--permission ${quote permission}"
          ) cfg.hub.permissions}
      ''}

      ${lib.concatMapStringsSep "\n" (
        plugin: "paseo --home ${quote cfg.stateDir} plugin add ${quote plugin.source}"
      ) plugins}
    '';
  };
in
{
  options.my.features.dev.paseo.daemon = {
    enable = lib.mkEnableOption "the Paseo daemon";

    package = lib.mkOption {
      type = lib.types.package;
      default = inputs.paseo.packages.${system}.paseo;
      defaultText = lib.literalExpression "inputs.paseo.packages.${pkgs.stdenv.hostPlatform.system}.paseo";
      description = "Paseo package, from the upstream flake by default.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      # 6767 is Bazarr's port; a daemon that collides with a media service on one host fails only
      # there, which is the kind of defect nobody finds by reading the module.
      default = 6867;
      description = "Daemon port, reachable by peers over the mesh.";
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = config.my.topology.hosts.${hostName}.wireguardIpv4;
      defaultText = lib.literalExpression "the host's WireGuard address";
      description = ''
        Address the daemon binds. The default is the mesh address, so the peers reach it and
        nothing outside the mesh does.
      '';
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/paseo";
      description = "Paseo home: agents, workspaces, schedules, plugins and daemon identity.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "paseo";
      description = "Account the daemon runs as; also the owner of the agent credentials.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "paseo";
      description = "Group of the daemon account and its state directory.";
    };

    relay = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether the daemon opens the upstream relay for remote pairing. Off by default: the mesh
        already reaches every host, so the relay would add a path nobody needs.
      '';
    };

    connectPeers = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Register every other daemon host as a saved peer. The registration is idempotent, so the
        unit runs on every boot and after a host joins the fleet.
      '';
    };

    hub = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Enroll this daemon with the Hub. Off until the credential exists: the API key is issued
          by a Hub operator account, and a declared secret whose key is absent fails activation.
          Enable it in the same change that adds the key to SOPS.
        '';
      };

      origin = lib.mkOption {
        type = lib.types.str;
        default = "https://paseo.vyrx.de";
        description = "Hub origin.";
      };

      apiKeySecret = lib.mkOption {
        type = lib.types.str;
        default = "services/paseo/hub_api_key";
        description = "SOPS secret holding the organization API key the daemon enrolls with.";
      };

      permissions = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "hub.execute" ];
        description = ''
          Grants the daemon requests while enrolling. A daemon that grants nothing stays visible
          to Hub but can never be a workflow target.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    users.groups.${cfg.group} = { };
    users.users.${cfg.user} = {
      isSystemUser = true;
      inherit (cfg) group;
      home = cfg.stateDir;
      description = "Paseo daemon";
    };

    systemd.services.paseo = {
      description = "Paseo daemon";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      environment = daemonEnv;
      # A systemd service starts with a minimal PATH, and the daemon is not self-contained: its
      # terminal worker reads its own process identity with `ps`, and the agents it spawns expect
      # git, bash and node. Without these the bootstrap fails and the unit restart-loops.
      path = [
        pkgs.procps
        pkgs.git
        pkgs.bashInteractive
        pkgs.nodejs_22
      ]
      ++ lib.optional config.my.features.dev.pi.enable config.my.features.dev.pi.package;
      serviceConfig = {
        Type = "simple";
        ExecStart = "${paseo} daemon run --home ${cfg.stateDir}";
        User = cfg.user;
        Group = cfg.group;
        StateDirectory = baseNameOf cfg.stateDir;
        # A state directory created before this unit carried User= is owned by root, and
        # StateDirectory only fixes the top level. Reclaiming it on every start is idempotent and
        # keeps a host that was deployed during the bug from failing on its own files.
        ExecStartPre = [ "+${pkgs.coreutils}/bin/chown -R ${cfg.user}:${cfg.group} ${cfg.stateDir}" ];
        Restart = "always";
        RestartSec = 2;
        # The daemon spawns agent CLIs, so it needs a writable home and a normal PATH. Keep the
        # kill mode to the main process: agent processes are its children by design.
        KillMode = "mixed";
      };
    };

    systemd.services.paseo-configure = {
      description = "Reconcile Paseo peers, Hub enrollment and plugins";
      wantedBy = [ "multi-user.target" ];
      after = [ "paseo.service" ];
      requires = [ "paseo.service" ];
      environment = daemonEnv;
      path = [
        pkgs.procps
        pkgs.git
        pkgs.bashInteractive
        pkgs.nodejs_22
      ]
      ++ lib.optional config.my.features.dev.pi.enable config.my.features.dev.pi.package;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = cfg.user;
        Group = cfg.group;
        StateDirectory = baseNameOf cfg.stateDir;
        ExecStart = "${configure}/bin/paseo-configure";
      };
    };

    # The daemon is a TCP listener on the mesh, not an HTTP service behind the ingress. It
    # declares direct access instead of a publication: the firewall rule then comes from the same
    # statement the daemon binds to, and no port is opened beyond the WireGuard interface.
    my.contracts.provides.paseo-daemon = {
      endpoints.daemon = {
        port = cfg.port;
        protocol = "tcp";
        directAccess = {
          enable = true;
          protocol = "tcp";
          interface = "wireguard";
        };
      };
    };

    # The daemon reads the key, so it must be able to; nobody else needs it.
    sops.secrets.${cfg.hub.apiKeySecret} = lib.mkIf cfg.hub.enable {
      owner = cfg.user;
      mode = "0400";
    };
  };
}
