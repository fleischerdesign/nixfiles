{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.features.dev.openchamber;
  ownHost = config.my.topology.hosts.${config.networking.hostName} or null;
in
{
  options.my.features.dev.openchamber = {
    enable = lib.mkEnableOption "OpenChamber workspace for Home Manager users";

    web.enable = lib.mkEnableOption "OpenChamber web and CLI interface";
    desktop.enable = lib.mkEnableOption "OpenChamber desktop interface";

    server = {
      enable = lib.mkEnableOption "a headless OpenChamber server bound to this host mesh address";

      port = lib.mkOption {
        type = lib.types.port;
        default = 3000;
        description = "TCP port the headless server listens on, on the mesh address of the host.";
      };
    };
  };

  config = lib.mkMerge [
    {
      assertions =
        lib.optionals cfg.enable [
          {
            assertion = config.my.features.dev.opencode.enable;
            message = "OpenChamber requires the OpenCode feature on this host.";
          }
          {
            assertion = cfg.web.enable || cfg.desktop.enable || cfg.server.enable;
            message = "OpenChamber must enable at least one interface.";
          }
          {
            assertion = !cfg.desktop.enable || pkgs.stdenv.hostPlatform.system == "x86_64-linux";
            message = "The OpenChamber desktop package is available only on x86_64-linux.";
          }
        ]
        ++ lib.optionals (cfg.enable && cfg.server.enable) [
          {
            # The bind address and the firewall rule are both derived from the inventory entry, so
            # a host without a mesh address cannot silently serve on the wrong one.
            assertion = ownHost != null && ownHost.wireguardIpv4 != null;
            message = "The OpenChamber server binds the mesh address, but ${config.networking.hostName} declares no wireguardIpv4.";
          }
        ];

      home-manager.sharedModules = [ ./home.nix ];
    }

    # The port is opened for the mesh and for the mesh alone, and only while the feature is on:
    # the firewall renders it from the contract like every other permission in this fleet. With
    # the feature off nothing is declared, so no service entry is left behind to offer nothing.
    (lib.mkIf (cfg.enable && cfg.server.enable) {
      my.contracts.provides.openchamber.endpoints.ui = {
        port = cfg.server.port;
        protocol = "tcp";
        directAccess = {
          enable = true;
          interface = "wireguard";
          protocol = "tcp";
        };
      };
    })
  ];
}
