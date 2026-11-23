{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.my.features.dev.openchamber;
  systems = (import ../../../lib/fleet-configs.nix { inherit lib; }).systems config;
  peers = lib.filterAttrs (_: system: system.config.my.features.dev.openchamber.enable) systems;
  desktopPeers = lib.filterAttrs (
    _: system: system.config.my.features.dev.openchamber.role != "server"
  ) peers;
  hasDesktop = cfg.role != "server";
  hasServer = cfg.role != "desktop";
  primary = config.my.user.primary;
  primaryHome = config.users.users.${primary}.home;
  address = config.my.topology.hosts.${config.networking.hostName}.wireguardIpv4 or null;
  accountPlan = pkgs.writeText "openchamber-subscriptions.json" (
    builtins.toJSON (
      map (subscription: {
        inherit (subscription) name;
        path = config.sops.secrets.${subscription.apiKeySecret}.path;
      }) cfg.subscriptions
    )
  );
  accountUnit = "openchamber-accounts";
  packages = import ./package.nix {
    inherit lib pkgs;
    upstream = inputs.openchamber.packages.${pkgs.stdenv.hostPlatform.system};
  };
  serverCommand = pkgs.writeShellScript "openchamber-server" ''
    set -eu
    ${lib.optionalString (cfg.server.uiPasswordSecret != null) ''
      export OPENCHAMBER_UI_PASSWORD="$(cat "$CREDENTIALS_DIRECTORY/ui-password")"
    ''}
    ${lib.optionalString (cfg.server.uiPasswordSecret == null) ''
      password_file="${primaryHome}/.local/state/openchamber/server-ui-password"
      if [ ! -s "$password_file" ]; then
        ${pkgs.coreutils}/bin/install -d -m 700 "$(dirname "$password_file")"
        (umask 077; ${pkgs.openssl}/bin/openssl rand -base64 32 > "$password_file")
      fi
      export OPENCHAMBER_UI_PASSWORD="$(cat "$password_file")"
    ''}
    exec ${packages.server}/bin/openchamber serve --port ${toString cfg.server.port} --lan --api-only
  '';
in
{

  options.my.features.dev.openchamber = {
    enable = lib.mkEnableOption "OpenChamber desktop and native fleet pairing";
    role = lib.mkOption {
      type = lib.types.enum [
        "desktop"
        "server"
        "both"
      ];
      default = "desktop";
      description = ''
        Desktop installs the Electron client and native fleet pairing. Server installs only a
        headless `openchamber serve` runtime for clients on other hosts. Both runs both.
      '';
    };
    server = {
      port = lib.mkOption {
        type = lib.types.port;
        default = 7338;
        description = "Headless OpenChamber server port.";
      };
      uiPasswordSecret = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          SOPS secret for the headless server UI password. Null generates a password once at
          ~/.local/state/openchamber/server-ui-password.
        '';
      };
    };
    autostart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Start OpenChamber Desktop at login through the XDG autostart entry. The desktop's own
        toggle reflects the file's existence; the next activation restores a disabled entry.
      '';
    };
    subscriptions = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption { type = lib.types.strMatching "[a-zA-Z0-9_-]+"; };
            apiKeySecret = lib.mkOption { type = lib.types.str; };
          };
        }
      );
      default = [ ];
      description = "Named Go API keys from SOPS, reconciled into OpenCode's credential store.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 7337;
      description = "Desktop network port, shared by runtime settings and the WireGuard endpoint.";
    };
    defaultHost = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "[a-zA-Z0-9_-]+");
      default = null;
      description = ''
        Peer name the desktop selects at startup. Null keeps Local; an offline peer falls back
        to Local through OpenChamber's normal boot probe.
      '';
    };
    uiPasswordSecret = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        SOPS secret holding the desktop UI password. Null generates a random password on the
        first activation and keeps it in the mode-0600 settings file.
      '';
    };
    packages = lib.mkOption {
      type = lib.types.attrsOf lib.types.package;
      readOnly = true;
      internal = true;
      default = packages;
    };
    peers = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      readOnly = true;
      internal = true;
      default = lib.mapAttrs (name: system: {
        user = system.config.my.user.primary;
        address = config.my.topology.hosts.${name}.wireguardIpv4;
        port = system.config.my.features.dev.openchamber.port;
        sshPort = system.config.my.contracts.provides.ssh.endpoints.ssh.port;
      }) (lib.filterAttrs (name: _: name != config.networking.hostName) peers);
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion =
          config.my.features.system.networking.ssh.enable
          && lib.all (peer: peer.address != null) (lib.attrValues cfg.peers);
        message = "OpenChamber native enrollment requires SSH and a WireGuard address for each desktop peer";
      }

      {
        assertion =
          lib.length (lib.unique (map (subscription: subscription.name) cfg.subscriptions))
          == lib.length cfg.subscriptions;
        message = "OpenChamber subscription names must be unique";
      }

      {
        assertion = !hasDesktop || cfg.defaultHost == null || builtins.hasAttr cfg.defaultHost cfg.peers;
        message = "OpenChamber defaultHost must name an enabled desktop peer";
      }

      {
        assertion = !hasServer || address != null;
        message = "OpenChamber server role requires a WireGuard address";
      }

      {
        assertion = cfg.role != "both" || cfg.port != cfg.server.port;
        message = "OpenChamber desktop and server ports must differ when role = \"both\"";
      }
    ];
    sops.secrets =
      lib.listToAttrs (
        map (
          subscription:
          lib.nameValuePair subscription.apiKeySecret {
            owner = lib.mkDefault config.my.user.primary;
            restartUnits = [ "${accountUnit}.service" ];
          }
        ) cfg.subscriptions
      )
      // lib.optionalAttrs (cfg.uiPasswordSecret != null) {
        ${cfg.uiPasswordSecret} = {
          owner = lib.mkDefault config.my.user.primary;
        };
      }
      // lib.optionalAttrs (hasServer && cfg.server.uiPasswordSecret != null) {
        ${cfg.server.uiPasswordSecret} = {
          owner = lib.mkDefault config.my.user.primary;
        };
      };
    systemd.services.${accountUnit} = {
      description = "Reconcile this device's declared OpenCode accounts";
      wantedBy = [ "multi-user.target" ];
      after = [ "home-manager-${primary}.service" ];
      environment.HOME = primaryHome;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = primary;
        WorkingDirectory = primaryHome;
        UMask = "0077";
        TimeoutStartSec = 180;
        ExecStart = "${pkgs.python3}/bin/python ${
          builtins.path {
            path = ./credentials.py;
            name = "openchamber-credentials.py";
          }
        } ${packages.opencode}/bin/opencode ${accountPlan}";
      };
    };
    systemd.services.openchamber-server = lib.mkIf hasServer {
      description = "OpenChamber headless server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      environment = {
        HOME = primaryHome;
        XDG_CONFIG_HOME = "${primaryHome}/.config";
      };
      serviceConfig = {
        Type = "simple";
        User = primary;
        WorkingDirectory = primaryHome;
        UMask = "0077";
        ExecStart = serverCommand;
        Restart = "on-failure";
        RestartSec = 5;
        TimeoutStopSec = 30;
        LoadCredential =
          lib.optional (cfg.server.uiPasswordSecret != null)
            "ui-password:${config.sops.secrets.${cfg.server.uiPasswordSecret}.path}";
      };
    };
    my.contracts.provides.openchamber.endpoints =
      lib.optionalAttrs hasDesktop {
        desktop = {
          inherit (cfg) port;
          directAccess = {
            enable = desktopPeers != { };
            interface = "wireguard";
            fromHosts = lib.attrNames desktopPeers;
          };
        };
      }
      // lib.optionalAttrs hasServer {
        server = {
          inherit (cfg.server) port;
          directAccess = {
            enable = desktopPeers != { };
            interface = "wireguard";
            fromHosts = lib.attrNames desktopPeers;
          };
        };
      };
    my.features.system.networking.ssh.admitsHosts = lib.attrNames desktopPeers;
    home-manager.sharedModules = lib.optionals hasDesktop [ ./home.nix ];
  };
}
