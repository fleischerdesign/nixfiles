# extensions/rpiv-questions/default.nix
{ config, lib, ... }:
let
  cfg = config.my.features.dev.pi.extensions.rpiv-questions;
in
{
  options.my.features.dev.pi.extensions.rpiv-questions = {
    enable = lib.mkEnableOption "rpiv-ask-user-question";
    collapseKey = lib.mkOption {
      type = lib.types.str;
      default = "ctrl+]";
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
    my.features.dev.pi.extensions.rpiv-questions._files.config.".config/rpiv-ask-user-question/config.json" =
      {
        collapseKey = cfg.collapseKey;
      };
  };
}
