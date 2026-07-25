# extensions/web-access/default.nix
{ config, lib, ... }:
let
  cfg = config.my.features.dev.pi.extensions.web-access;
  piLib = {
    inherit (import ../../lib/extension-files.nix { inherit lib; }) filesModule;
    inherit (import ../../lib/extra-settings.nix { inherit lib; }) scalarExtraSettings mkCheckShadowing;
  };
  extPath = "my.features.dev.pi.extensions.web-access";
  knownKeys = [
    "workflow"
    "chromeProfile"
    "allowBrowserCookies"
    "geminiBaseUrl"
    "braveApiKey"
    "exaApiKey"
    "geminiApiKey"
    "cloudflareApiKey"
    "tavilyApiKey"
    "parallelApiKey"
    "perplexityApiKey"
  ];
in
{
  options.my.features.dev.pi.extensions.web-access = {
    enable = lib.mkEnableOption "pi-web-access";
    package = lib.mkOption {
      type = lib.types.str;
      default = "npm:pi-web-access";
      description = "NPM package specifier for this extension.";
    };
    workflow = lib.mkOption {
      type = lib.types.enum [
        "none"
        "summary-review"
        "auto-summary"
      ];
      default = "auto-summary";
    };
    chromeProfile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };
    allowBrowserCookies = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
    geminiBaseUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };
    braveApiKey = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };
    exaApiKey = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };
    geminiApiKey = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };
    cloudflareApiKey = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };
    tavilyApiKey = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };
    parallelApiKey = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };
    perplexityApiKey = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
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

    my.features.dev.pi.extensions.web-access._files.config.".pi/web-search.json" =
      lib.filterAttrs (_: v: v != null && v != false)
        (
          {
            inherit (cfg)
              workflow
              chromeProfile
              allowBrowserCookies
              geminiBaseUrl
              braveApiKey
              exaApiKey
              geminiApiKey
              cloudflareApiKey
              tavilyApiKey
              parallelApiKey
              perplexityApiKey
              ;
          }
          // cfg.extraSettings
        );
  };
}
