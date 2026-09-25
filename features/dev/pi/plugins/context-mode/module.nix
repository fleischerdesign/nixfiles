# features/dev/pi/plugins/context-mode/module.nix
# Context trimming & summarization plugin for Pi.
{
  config,
  lib,
  ...
}:
let
  cfg = config.my.features.dev.pi.plugins.context-mode;
  piCfg = config.my.features.dev.pi;
in
{
  options.my.features.dev.pi.plugins.context-mode = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable context trimming & summarization plugin.";
    };

    extraConfig = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Additional raw options merged into ~/.pi/agent/context-mode.json.";
    };
  };

  config = lib.mkIf (piCfg.enable && cfg.enable && cfg.extraConfig != { }) {
    home-manager.sharedModules = [
      (
        {
          config,
          lib,
          ...
        }:
        let
          userPiCfg = config.my.features.dev.pi;
        in
        {
          config = lib.mkIf userPiCfg.enable {
            home.file.".pi/agent/context-mode.json".text = builtins.toJSON cfg.extraConfig;
          };
        }
      )
    ];
  };
}
