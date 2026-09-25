# features/dev/pi/plugins/pi-goal-x/module.nix
# Conversational goal planning, ordered Sisyphus flows, and completion auditor for Pi.
{
  config,
  lib,
  ...
}:
let
  cfg = config.my.features.dev.pi.plugins.pi-goal-x;
  piCfg = config.my.features.dev.pi;
in
{
  options.my.features.dev.pi.plugins.pi-goal-x = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable pi-goal-x conversational goal planning and autonomous completion auditor.";
    };

    auditorModel = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional model override for the independent completion auditor (defaults to current Pi model).";
    };

    auditorProvider = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional provider override for the completion auditor.";
    };

    extraConfig = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Additional raw options merged into ~/.pi/pi-goal-x-settings.json.";
    };
  };

  config = lib.mkIf (piCfg.enable && cfg.enable) {
    home-manager.sharedModules = [
      (
        {
          config,
          lib,
          ...
        }:
        let
          userPiCfg = config.my.features.dev.pi;

          baseSettings =
            lib.optionalAttrs (cfg.auditorModel != null) {
              model = cfg.auditorModel;
            }
            // lib.optionalAttrs (cfg.auditorProvider != null) {
              provider = cfg.auditorProvider;
            };

          mergedSettings = lib.recursiveUpdate baseSettings cfg.extraConfig;
        in
        {
          config = lib.mkIf userPiCfg.enable {
            home.file.".pi/pi-goal-x-settings.json" = lib.mkIf (mergedSettings != { }) {
              text = builtins.toJSON mergedSettings;
            };
          };
        }
      )
    ];
  };
}
