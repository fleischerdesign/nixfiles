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
  hasDesktop = cfg.role != "server";
  hasServer = cfg.role != "desktop";
  primary = config.my.user.primary;
  primaryHome = config.users.users.${primary}.home;
  address = config.my.topology.hosts.${config.networking.hostName}.wireguardIpv4 or null;
  clientHosts = lib.filter (
    name:
    name != config.networking.hostName
    && (config.my.topology.hosts.${name}.hostType or null) == "client"
    && (config.my.topology.hosts.${name}.wireguardIpv4 or null) != null
  ) (lib.attrNames config.my.topology.hosts);
  endpointClients = lib.unique (lib.attrNames cfg.peers ++ clientHosts);
  accountPlan = pkgs.writeText "openchamber-subscriptions.json" (
    builtins.toJSON (
      map (subscription: {
        inherit (subscription) name;
        path = config.sops.secrets.${subscription.apiKeySecret}.path;
      }) cfg.subscriptions
    )
  );
  accountUnit = "openchamber-accounts";
  fleetExtension = pkgs.runCommand "openchamber-builtin-fleet" { } ''
    mkdir -p $out/plugin
    cp -r ${
      inputs.openchamber-fleet.packages.${pkgs.stdenv.hostPlatform.system}.controller
    }/lib/node_modules/openchamber-fleet/dist $out/plugin/dist
    cat > $out/plugin/package.json <<'JSON'
    {
      "name": "openchamber-fleet-plugin",
      "version": "0.1.0",
      "type": "module",
      "exports": { ".": "./dist/plugin/index.js" }
    }
    JSON
    cat > $out/package.json <<'JSON'
    {
      "name": "openchamber-builtin-fleet",
      "version": "0.1.0",
      "type": "module",
      "openchamber": {
        "apiVersion": 1,
        "engines": { "openchamber": ">=2.8.0" },
        "id": "openchamber-builtin-fleet",
        "name": "Fleet",
        "icon": "cpu",
        "contributes": { "opencodePlugin": "plugin" }
      }
    }
    JSON
  '';
  packages = import ./package.nix {
    inherit lib pkgs;
    upstream = inputs.openchamber.packages.${pkgs.stdenv.hostPlatform.system};
    extraPlugins = [
      {
        name = "fleet";
        id = "openchamber-builtin-fleet";
        source = fleetExtension;
      }
    ];
  };
  serverCommand = pkgs.writeShellScript "openchamber-server" ''
    set -eu
    ${lib.optionalString (cfg.server.uiPasswordSecret != null) ''
      OPENCHAMBER_UI_PASSWORD="$(cat "$CREDENTIALS_DIRECTORY/ui-password")"
      export OPENCHAMBER_UI_PASSWORD
    ''}
    ${lib.optionalString (cfg.server.uiPasswordSecret == null) ''
      password_file="${primaryHome}/.local/state/openchamber/server-ui-password"
      if [ ! -s "$password_file" ]; then
        ${pkgs.coreutils}/bin/install -d -m 700 "$(dirname "$password_file")"
        (umask 077; ${pkgs.openssl}/bin/openssl rand -base64 32 > "$password_file")
      fi
      OPENCHAMBER_UI_PASSWORD="$(cat "$password_file")"
      export OPENCHAMBER_UI_PASSWORD
    ''}
    exec ${packages.server}/bin/openchamber serve --foreground --port ${toString cfg.server.port} --lan --api-only
  '';
  serverPushPlan = pkgs.writeText "openchamber-server-push.json" (
    builtins.toJSON {
      host = config.networking.hostName;
      desktops = lib.mapAttrs (_: peer: {
        inherit (peer) user address sshPort;
      }) cfg.peers;
    }
  );
  serverPush = pkgs.runCommand "openchamber-server-push" { } ''
    mkdir -p $out
    cp ${./server_enroll.py} $out/server_enroll.py
    cp ${./server_push.py} $out/server_push.py
  '';
  serverEnroll = pkgs.writeShellApplication {
    name = "openchamber-server-enroll";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      exec ${pkgs.python3}/bin/python ${
        builtins.path {
          path = ./server_enroll.py;
          name = "openchamber-server-enroll.py";
        }
      } ${toString cfg.server.port} ${
        if cfg.server.uiPasswordSecret != null then
          config.sops.secrets.${cfg.server.uiPasswordSecret}.path
        else
          "${primaryHome}/.local/state/openchamber/server-ui-password"
      } "$@"
    '';
  };
  serverPair = pkgs.writeShellApplication {
    name = "openchamber-server-pair";
    text = ''
      password_file=${
        if cfg.server.uiPasswordSecret != null then
          config.sops.secrets.${cfg.server.uiPasswordSecret}.path
        else
          "${primaryHome}/.local/state/openchamber/server-ui-password"
      }
      if [ -s "$password_file" ]; then
        OPENCHAMBER_UI_PASSWORD="$(cat "$password_file")"
        export OPENCHAMBER_UI_PASSWORD
      fi
      exec ${packages.server}/bin/openchamber connect-url \
        --port ${toString cfg.server.port} \
        --server ${lib.escapeShellArg "http://${address}:${toString cfg.server.port}"} \
        --qr "$@"
    '';
  };
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
    serverOnlyClients = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        When true a desktop exposes only the declared server hosts in its host list: no desktop
        peers are seeded or enrolled. Local remains the client's offline fallback.
      '';
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
      default =
        lib.mapAttrs
          (name: system: {
            user = system.config.my.user.primary;
            address = config.my.topology.hosts.${name}.wireguardIpv4;
            port = system.config.my.features.dev.openchamber.port;
            sshPort = system.config.my.contracts.provides.ssh.endpoints.ssh.port;
          })
          (
            lib.filterAttrs (
              name: system:
              name != config.networking.hostName && system.config.my.features.dev.openchamber.role != "server"
            ) peers
          );
    };
    serverPeers = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      readOnly = true;
      internal = true;
      default =
        lib.mapAttrs
          (name: system: {
            user = system.config.my.user.primary;
            address = config.my.topology.hosts.${name}.wireguardIpv4;
            port = system.config.my.features.dev.openchamber.server.port;
            sshPort = system.config.my.contracts.provides.ssh.endpoints.ssh.port;
          })
          (
            lib.filterAttrs (
              name: system:
              name != config.networking.hostName && system.config.my.features.dev.openchamber.role == "server"
            ) peers
          );
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
        assertion =
          !hasDesktop
          || cfg.defaultHost == null
          || builtins.hasAttr cfg.defaultHost cfg.peers
          || builtins.hasAttr cfg.defaultHost cfg.serverPeers;
        message = "OpenChamber defaultHost must name an enabled desktop or server peer";
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
    systemd.services.openchamber-server-enroll = lib.mkIf hasServer {
      description = "Deliver OpenChamber server tokens to declared desktops";
      wantedBy = [ "multi-user.target" ];
      after = [
        "${accountUnit}.service"
        "openchamber-server.service"
      ];
      wants = [ "openchamber-server.service" ];
      path = [ pkgs.openssh ];
      serviceConfig = {
        Type = "oneshot";
        User = primary;
        WorkingDirectory = primaryHome;
        UMask = "0077";
      };
      script = ''
        exec ${pkgs.python3}/bin/python ${serverPush}/server_push.py ${toString cfg.server.port} ${
          if cfg.server.uiPasswordSecret != null then
            config.sops.secrets.${cfg.server.uiPasswordSecret}.path
          else
            "${primaryHome}/.local/state/openchamber/server-ui-password"
        } ${serverPushPlan}
      '';
    };
    systemd.timers.openchamber-server-enroll = lib.mkIf hasServer {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2m";
        OnUnitInactiveSec = "10m";
      };
    };
    systemd.services.openchamber-server = lib.mkIf hasServer {
      description = "OpenChamber headless server";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network-online.target"
        "${accountUnit}.service"
      ];
      wants = [
        "network-online.target"
        "${accountUnit}.service"
      ];
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
        Restart = "always";
        RestartSec = 5;
        TimeoutStopSec = 30;
        LoadCredential =
          lib.optional (cfg.server.uiPasswordSecret != null)
            "ui-password:${config.sops.secrets.${cfg.server.uiPasswordSecret}.path}";
      };
    };
    environment.systemPackages = [
      inputs.openchamber-fleet.packages.${pkgs.stdenv.hostPlatform.system}.fleet-agent
    ]
    ++ lib.optionals hasServer [
      packages.server
      packages.opencode
      serverPair
      serverEnroll
    ];
    my.contracts.provides.openchamber.endpoints =
      lib.optionalAttrs hasDesktop {
        desktop = {
          inherit (cfg) port;
          directAccess = {
            enable = endpointClients != [ ];
            interface = "wireguard";
            fromHosts = endpointClients;
          };
        };
      }
      // lib.optionalAttrs hasServer {
        server = {
          inherit (cfg.server) port;
          directAccess = {
            enable = endpointClients != [ ];
            interface = "wireguard";
            fromHosts = endpointClients;
          };
        };
      };
    my.features.system.networking.ssh.admitsHosts = lib.attrNames cfg.peers;
    home-manager.sharedModules = lib.optionals hasDesktop [ ./home.nix ];
  };
}
