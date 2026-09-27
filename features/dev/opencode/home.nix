# features/dev/opencode/home.nix - the per-user half of the OpenCode feature.
{
  config,
  lib,
  osConfig ? { },
  ...
}:
let
  system = osConfig.my.features.dev.opencode;

  userCfg = config.my.features.dev.opencode;

  settings = lib.recursiveUpdate (
    {
      "$schema" = "https://opencode.ai/config.json";
      update = "disable";
    }
    // lib.optionalAttrs (system.model != null) { model = system.model; }
  ) system.settings;
in
{
  options.my.features.dev.opencode.enable = lib.mkEnableOption "OpenCode v2 for this user";

  config = lib.mkIf (system.enable && userCfg.enable) {
    home.packages = [ system.package ];
    xdg.configFile."opencode/opencode.json".text = builtins.toJSON settings;
  };
}
