# features/dev/pi/plugins/rpiv-ask-user-question/module.nix
# Structured questionnaire extension for Pi.
{
  config,
  lib,
  ...
}:
let
  cfg = config.my.features.dev.pi.plugins.rpiv-ask-user-question;
  piCfg = config.my.features.dev.pi;
in
{
  options.my.features.dev.pi.plugins.rpiv-ask-user-question = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable structured interactive questionnaire extension for Pi.";
    };

    extraConfig = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Additional raw options merged into ~/.pi/agent/ask-user-question.json.";
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
            home.file.".pi/agent/ask-user-question.json".text = builtins.toJSON cfg.extraConfig;
          };
        }
      )
    ];
  };
}
