# features/dev/openchamber/home.nix - the per-user half of the OpenChamber feature.
{
  config,
  lib,
  pkgs,
  osConfig ? { },
  ...
}:
let
  system = osConfig.my.features.dev.openchamber;

  # The launchers are rebuilt here from the same declarations the system side reads. They are pure
  # derivations of the OpenCode binary, so deriving them again is not a second fact - it is the same
  # fact read where it is used.
  opencodeBinary = "${osConfig.my.features.dev.opencode.package}/bin/opencode";
  withOpenCode =
    name: target:
    pkgs.writeShellScriptBin name ''
      export OPENCODE_BINARY=${lib.escapeShellArg opencodeBinary}
      exec ${target} "$@"
    '';
  web = withOpenCode "openchamber" "${pkgs.custom.openchamber-web}/bin/openchamber";
  desktop = withOpenCode "openchamber-desktop" "${pkgs.custom.openchamber-desktop}/bin/openchamber-desktop";

  userCfg = config.my.features.dev.openchamber;
in
{
  options.my.features.dev.openchamber.enable = lib.mkEnableOption "OpenChamber for this user";

  config = lib.mkIf (system.enable && userCfg.enable) {
    assertions = [
      {
        assertion = config.my.features.dev.opencode.enable;
        message = "OpenChamber requires OpenCode for the same Home Manager user.";
      }
    ];

    home.packages =
      lib.optionals system.web.enable [ web ] ++ lib.optionals system.desktop.enable [ desktop ];

    xdg.desktopEntries.openchamber = lib.mkIf system.desktop.enable {
      name = "OpenChamber";
      genericName = "Coding workspace";
      exec = "${desktop}/bin/openchamber-desktop";
      icon = "${pkgs.custom.openchamber-desktop}/share/icons/hicolor/scalable/apps/openchamber.svg";
      categories = [ "Development" ];
      terminal = false;
    };
  };
}
