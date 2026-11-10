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

  options.my.features.dev.openchamber = {
    enable = lib.mkEnableOption "OpenChamber desktop and native fleet pairing";
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
        message = "OpenChamber native enrollment requires SSH and a WireGuard address for each peer";
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
        }
      ) cfg.subscriptions
    );
    my.contracts.provides.openchamber.endpoints.desktop = {
      inherit (cfg) port;
      directAccess = {
        enable = cfg.peers != { };
        interface = "wireguard";
        fromHosts = lib.attrNames cfg.peers;
      };
    };
    environment.systemPackages = [ pkgs.curl ];
    my.features.system.networking.ssh.admitsHosts = lib.attrNames cfg.peers;
    home-manager.sharedModules = [ ./home.nix ];
  };
}
