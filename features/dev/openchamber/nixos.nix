{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.features.dev.openchamber;
in
{
  options.my.features.dev.openchamber = {
    enable = lib.mkEnableOption "OpenChamber workspace for Home Manager users";

    web.enable = lib.mkEnableOption "OpenChamber web and CLI interface";
    desktop.enable = lib.mkEnableOption "OpenChamber desktop interface";
  };

  config = {
    assertions = lib.optionals cfg.enable [
      {
        assertion = config.my.features.dev.opencode.enable;
        message = "OpenChamber requires the OpenCode feature on this host.";
      }
      {
        assertion = cfg.web.enable || cfg.desktop.enable;
        message = "OpenChamber must enable at least one interface.";
      }
      {
        assertion = !cfg.desktop.enable || pkgs.stdenv.hostPlatform.system == "x86_64-linux";
        message = "The OpenChamber desktop package is available only on x86_64-linux.";
      }
    ];

    home-manager.sharedModules = [ ./home.nix ];
  };
}
