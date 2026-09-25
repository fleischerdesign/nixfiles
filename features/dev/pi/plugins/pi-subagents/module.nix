# features/dev/pi/plugins/pi-subagents/module.nix
# Single-agent delegation and scripted multi-agent workflows for Pi.
{
  config,
  lib,
  ...
}:
let
  cfg = config.my.features.dev.pi.plugins.pi-subagents;
  piCfg = config.my.features.dev.pi;
in
{
  options.my.features.dev.pi.plugins.pi-subagents = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable pi-subagents delegation and multi-agent workflow plugin.";
    };

    defaultModel = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "deepseek-flash";
      description = "Default low-cost model for subagents (scout, researcher, reviewer).";
    };

    extraConfig = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Additional raw options merged into ~/.pi/agent/extensions/subagent/config.json.";
    };
  };

  config = lib.mkIf (piCfg.enable && cfg.enable) {
    # Set settings-level subagents options into Pi settings
    my.features.dev.pi.settings = {
      subagents = lib.mkMerge [
        (lib.optionalAttrs (cfg.defaultModel != null) {
          defaultModel = cfg.defaultModel;
        })
      ];
    };

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
            home.file.".pi/agent/extensions/subagent/config.json" = lib.mkIf (cfg.extraConfig != { }) {
              text = builtins.toJSON cfg.extraConfig;
            };
          };
        }
      )
    ];
  };
}
