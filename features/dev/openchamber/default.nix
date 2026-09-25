{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.features.dev.openchamber;
  opencodeBinary = "${config.my.features.dev.opencode.package}/bin/opencode";
  withOpenCode =
    name: target:
    pkgs.writeShellScriptBin name ''
      export OPENCODE_BINARY=${lib.escapeShellArg opencodeBinary}
      exec ${target} "$@"
    '';
  web = withOpenCode "openchamber" "${pkgs.custom.openchamber-web}/bin/openchamber";
  desktop = withOpenCode "openchamber-desktop" "${pkgs.custom.openchamber-desktop}/bin/openchamber-desktop";
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
        assertion = !cfg.desktop.enable || pkgs.system == "x86_64-linux";
        message = "The OpenChamber desktop package is available only on x86_64-linux.";
      }
    ];

    home-manager.sharedModules = [
      (
        { config, lib, ... }:
        let
          userCfg = config.my.features.dev.openchamber;
        in
        {
          options.my.features.dev.openchamber.enable = lib.mkEnableOption "OpenChamber for this user";

          config = lib.mkIf (cfg.enable && userCfg.enable) {
            assertions = [
              {
                assertion = config.my.features.dev.opencode.enable;
                message = "OpenChamber requires OpenCode for the same Home Manager user.";
              }
            ];

            home.packages =
              lib.optionals cfg.web.enable [ web ] ++ lib.optionals cfg.desktop.enable [ desktop ];

            xdg.desktopEntries.openchamber = lib.mkIf cfg.desktop.enable {
              name = "OpenChamber";
              genericName = "Coding workspace";
              exec = "${desktop}/bin/openchamber-desktop";
              icon = "${pkgs.custom.openchamber-desktop}/share/icons/hicolor/scalable/apps/openchamber.svg";
              categories = [ "Development" ];
              terminal = false;
            };
          };
        }
      )
    ];
  };
}
