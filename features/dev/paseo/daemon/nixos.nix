# The Paseo daemon: one per machine, owning that machine's agents, workspaces and schedules.
#
# Two scopes exist because the machine's role decides who the agents run as. A server has no login
# session, so its daemon is a system service with its own account. A workstation's agents use the
# user's own credentials - and the desktop app starts a daemon in the user's home anyway - so there
# the daemon is a user service instead of a second, credential-less copy.
#
# Peers are not configured here. A host that enables the daemon is a peer of every other one, and
# the address and port come from that peer's own evaluated configuration - the fleet decides the
# mesh once, in `inventory/hosts.nix`.
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
  plugins = (import ../plugins.nix { inherit lib; }).findPlugins ../plugins;

  peerSet = import ../peers.nix {
    inherit
      lib
      pkgs
      systems
      hostName
      plugins
      ;
    package = cfg.package;
    stateDir = cfg.stateDir;
    connectPeers = cfg.connectPeers;
    hub = {
      enable = cfg.hub.enable;
      inherit (cfg.hub) origin permissions;
      apiKeyPath = config.sops.secrets.${cfg.hub.apiKeySecret}.path;
    };
  };

  daemonEnv = {
    PASEO_HOME = cfg.stateDir;
    HOME = cfg.stateDir;
    PASEO_LISTEN = "${cfg.listenAddress}:${toString cfg.port}";
    PASEO_RELAY_ENABLED = lib.boolToString cfg.relay;
  };

  # A systemd service starts with a minimal PATH, and the daemon is not self-contained: its
  # terminal worker reads its own process identity with `ps`, and the agents it spawns expect git,
  # bash and node. Without these the bootstrap fails and the unit restart-loops.
  servicePath = [
    pkgs.procps
    pkgs.git
    pkgs.bashInteractive
    pkgs.nodejs_22
  ]
  ++ lib.optional config.my.features.dev.pi.enable config.my.features.dev.pi.package;
in
{
  options.my.features.dev.paseo.daemon = {
    enable = lib.mkEnableOption "the Paseo daemon";

    scope = lib.mkOption {
      type = lib.types.enum [
        "system"
        "user"
      ];
      default = "system";
      description = ''
        Who owns the daemon. `system` runs it as its own account from boot - the right shape for a
        server. `user` runs it as the logged-in user, with that user's credentials and the same
        `~/.paseo` the desktop app uses.
      '';
    };

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
      default =
        if cfg.scope == "user" then "0.0.0.0" else config.my.topology.hosts.${hostName}.wireguardIpv4;
      defaultText = lib.literalExpression "the mesh address, or 0.0.0.0 for a user daemon";
      description = ''
        Address the daemon binds. The system default is the mesh address, so peers reach it and
        nothing outside the mesh does. A user daemon binds every address because the desktop app
        expects its daemon on loopback; the firewall still admits the port on the mesh only.
      '';
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/paseo";
      description = ''
        Paseo home for a system daemon: agents, workspaces, schedules, plugins and identity. A user
        daemon uses `$HOME/.paseo`, which the app owns.
      '';
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "paseo";
      description = "Account a system daemon runs as; also the owner of the agent credentials.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "paseo";
      description = "Group of the system daemon account and its state directory.";
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
        Register every other daemon host as a saved peer. The reconciliation is idempotent, so it
        runs on every boot and after a host joins the fleet.
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

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      # The listener is a fact about the host either way, so the firewall rule is declared once.
      {
        # The daemon is a TCP listener on the mesh, not an HTTP service behind the ingress. It
        # declares direct access instead of a publication: the firewall rule then comes from the
        # same statement the daemon binds to, and no port is opened beyond the WireGuard interface.
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
      }

      (lib.mkIf (cfg.scope == "system") {
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
          path = servicePath;
          serviceConfig = {
            Type = "simple";
            ExecStart = "${cfg.package}/bin/paseo daemon run --home ${cfg.stateDir}";
            User = cfg.user;
            Group = cfg.group;
            StateDirectory = baseNameOf cfg.stateDir;
            # A state directory created before this unit carried User= is owned by root, and
            # StateDirectory only fixes the top level. Reclaiming it on every start is idempotent.
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
          path = servicePath;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = cfg.user;
            Group = cfg.group;
            StateDirectory = baseNameOf cfg.stateDir;
            ExecStart = "${peerSet.configure}/bin/paseo-configure";
            # Every request is bounded, and so is the unit: a peer that does not answer must not
            # hold the activation open, which is exactly what a hanging `host add` did.
            TimeoutStartSec = 300;
          };
        };

        # The daemon reads the key, so it must be able to; nobody else needs it.
        sops.secrets.${cfg.hub.apiKeySecret} = lib.mkIf cfg.hub.enable {
          owner = cfg.user;
          mode = "0400";
        };
      })

      (lib.mkIf (cfg.scope == "user") {
        home-manager.sharedModules = [ ./home.nix ];
      })
    ]
  );
}
