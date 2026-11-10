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
  packages = import ./package.nix {
    inherit lib pkgs;
    upstream = inputs.openchamber.packages.${pkgs.stdenv.hostPlatform.system};
  };
in
{
  imports = [ inputs.openchamber.nixosModules.openchamber ];

  options.my.features.dev.openchamber = {
    enable = lib.mkEnableOption "OpenChamber desktop and persistent local workspace";
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
      default = 3000;
      description = "Loopback port of the workspace reached through SSH.";
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
        message = "OpenChamber Remote Instances require SSH and a WireGuard address for each peer";
      }

      {
        assertion =
          lib.length (lib.unique (map (subscription: subscription.name) cfg.subscriptions))
          == lib.length cfg.subscriptions;
        message = "OpenChamber subscription names must be unique";
      }
    ];
    sops.secrets = lib.listToAttrs (
      map (
        subscription:
        lib.nameValuePair subscription.apiKeySecret {
          owner = lib.mkDefault config.my.user.primary;
          restartUnits = [ "openchamber.service" ];
        }
      ) cfg.subscriptions
    );
    systemd.services.openchamber = {
      serviceConfig.TimeoutStartSec = 120;
      postStart =
        let
          plan = pkgs.writeText "openchamber-credentials.json" (
            builtins.toJSON (
              map (subscription: {
                inherit (subscription) name;
                path = config.sops.secrets.${subscription.apiKeySecret}.path;
              }) cfg.subscriptions
            )
          );
          script = builtins.path {
            path = ./credentials.py;
            name = "openchamber-credentials.py";
          };
        in
        "${pkgs.python3}/bin/python ${script} http://127.0.0.1:${toString cfg.port} ${plan}";
    };
    services.openchamber = {
      enable = true;
      package = packages.server;
      user = config.my.user.primary;
      inherit (cfg) port;
    };
    environment.systemPackages = [ pkgs.curl ];
    my.features.system.networking.ssh.admitsHosts = lib.attrNames cfg.peers;
    home-manager.sharedModules = [ ./home.nix ];
  };
}
