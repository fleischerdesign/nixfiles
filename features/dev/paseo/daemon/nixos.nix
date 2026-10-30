# The Paseo daemon: one per machine, owning that machine's agents, workspaces and schedules.
#
# Peers are not configured here. A host that enables the daemon is a peer of every other one, and
# the address is the inventory's WireGuard address - the fleet decides the mesh once, in
# `inventory/hosts.nix`, and this module reads it instead of repeating it.
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
  daemonEnv = {
    PASEO_HOME = cfg.stateDir;
    HOME = cfg.stateDir;
    PASEO_LISTEN = "${cfg.listenAddress}:${toString cfg.port}";
    PASEO_RELAY_ENABLED = lib.boolToString cfg.relay;
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
      default = 6767;
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
      serviceConfig = {
        Type = "simple";
        ExecStart = "${paseo} daemon run --home ${cfg.stateDir}";
        inherit (cfg) user group;
        StateDirectory = baseNameOf cfg.stateDir;
        Restart = "always";
        RestartSec = 2;
        # The daemon spawns agent CLIs, so it needs a writable home and a normal PATH. Keep the
        # kill mode to the main process: agent processes are its children by design.
        KillMode = "mixed";
      };
    };

    # Peers and plugins are runtime state in `$PASEO_HOME`, because the daemon owns those files.
    # The unit therefore reconciles them on boot instead of writing them: a repeated registration
    # of an unchanged host returns the saved entry, so running this every start is a no-op unless
    # the fleet or the plugin list changed.
    systemd.services.paseo-configure = {
      description = "Register Paseo peers and declared plugins";
      wantedBy = [ "multi-user.target" ];
      after = [ "paseo.service" ];
      requires = [ "paseo.service" ];
      environment = daemonEnv;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        inherit (cfg) user group;
        StateDirectory = baseNameOf cfg.stateDir;
      };
      script = ''
        set -eu

        # The unit starts after the daemon, not when it is ready to answer; wait for the socket
        # instead of racing it.
        for _ in $(seq 1 60); do
          if ${paseo} --home ${cfg.stateDir} daemon status >/dev/null 2>&1; then
            break
          fi
          sleep 1
        done

        ${
          if cfg.connectPeers then
            lib.concatMapStringsSep "\n" (
              peer:
              let
                address = config.my.topology.hosts.${peer}.wireguardIpv4;
              in
              ''${paseo} --home ${cfg.stateDir} host add "tcp://${address}:${toString cfg.port}" --label ${peer} >/dev/null''
            ) (lib.attrNames peers)
          else
            ": peer registration disabled"
        }

        ${lib.concatMapStringsSep "\n" (
          plugin: ''${paseo} --home ${cfg.stateDir} plugin add "${plugin.source}" >/dev/null''
        ) plugins}
      '';
    };
  };
}
