# features/dev/pi/plugins/pi-background-tasks/module.nix
# Durable background shell tasks & async process management plugin for Pi.
{
  config,
  lib,
  ...
}:
let
  cfg = config.my.features.dev.pi.plugins.pi-background-tasks;
  piCfg = config.my.features.dev.pi;
in
{
  options.my.features.dev.pi.plugins.pi-background-tasks = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable durable background shell tasks & async process management plugin.";
    };

    extraConfig = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Additional raw options merged into ~/.pi/agent/background-tasks.json.";
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
            home.file.".pi/agent/background-tasks.json".text = builtins.toJSON cfg.extraConfig;
          };
        }
      )
    ];
  };
}
