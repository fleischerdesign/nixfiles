# extensions/pi-subagents/default.nix
{ config, lib, ... }:
let
  cfg = config.my.features.dev.pi.extensions.pi-subagents;
in
{
  options.my.features.dev.pi.extensions.pi-subagents = {
    enable = lib.mkEnableOption "pi-subagents";
    maxConcurrent = lib.mkOption {
      type = lib.types.ints.positive;
      default = 4;
    };
    defaultMaxTurns = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 0;
    };
    graceTurns = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 3;
    };
    defaultJoinMode = lib.mkOption {
      type = lib.types.enum [
        "group"
        "individual"
      ];
      default = "group";
    };
    schedulingEnabled = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
    scopeModels = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
    widgetMode = lib.mkOption {
      type = lib.types.enum [
        "all"
        "background"
        "off"
      ];
      default = "background";
    };
    extraSettings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
    };

    _files = lib.mkOption {
      type = lib.types.submodule {
        options.config = lib.mkOption {
          type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
          default = { };
        };
        options.assets = lib.mkOption {
          type = lib.types.attrsOf lib.types.path;
          default = { };
        };
      };
      default = { };
      description = "Files to deploy (set by extension, read by orchestrator).";
    };
  };

  config = lib.mkIf cfg.enable {
    my.features.dev.pi.extensions.pi-subagents._files = {
      config.".pi/agent/subagents.json" = {
        maxConcurrent = cfg.maxConcurrent;
        defaultMaxTurns = cfg.defaultMaxTurns;
        graceTurns = cfg.graceTurns;
        defaultJoinMode = cfg.defaultJoinMode;
        schedulingEnabled = cfg.schedulingEnabled;
        scopeModels = cfg.scopeModels;
        widgetMode = cfg.widgetMode;
      }
      // cfg.extraSettings;

      assets.".pi/agent/agents" = ./agents;
    };
  };
}
