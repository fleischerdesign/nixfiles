# extensions/rpiv-questions/default.nix
{ config, lib, ... }:
let
  cfg = config.my.features.dev.pi.extensions.rpiv-questions;
  piLib = {
    inherit (import ../../lib/extension-files.nix { inherit lib; }) filesModule;
    inherit (import ../../lib/extra-settings.nix { inherit lib; }) scalarExtraSettings mkCheckShadowing;
  };
  extPath = "my.features.dev.pi.extensions.rpiv-questions";
  knownKeys = [ "collapseKey" ];
in
{
  options.my.features.dev.pi.extensions.rpiv-questions = {
    enable = lib.mkEnableOption "rpiv-ask-user-question";
    package = lib.mkOption {
      type = lib.types.str;
      default = "npm:@juicesharp/rpiv-ask-user-question";
      description = "NPM package specifier for this extension.";
    };
    collapseKey = lib.mkOption {
      type = lib.types.str;
      default = "ctrl+]";
    };
    extraSettings = lib.mkOption ({ default = { }; } // piLib.scalarExtraSettings);

    _files = lib.mkOption {
      type = piLib.filesModule;
      default = { };
      description = "Files to deploy (set by extension, read by orchestrator).";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = piLib.mkCheckShadowing extPath knownKeys config;

    my.features.dev.pi.extensions.rpiv-questions._files.config.".config/rpiv-ask-user-question/config.json" =
    {
      inherit (cfg) collapseKey;
    }
    // cfg.extraSettings;
  };
}
