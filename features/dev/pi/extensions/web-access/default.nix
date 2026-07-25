# extensions/web-access/default.nix
{ config, lib, ... }:
let
  cfg = config.my.features.dev.pi.extensions.web-access;
in
{
  options.my.features.dev.pi.extensions.web-access = {
    enable = lib.mkEnableOption "pi-web-access";
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
    my.features.dev.pi.extensions.web-access._files.config.".pi/web-search.json" =
      lib.filterAttrs (_: v: v != null && v != false)
        (
          {
            workflow = cfg.workflow;
            chromeProfile = cfg.chromeProfile;
            allowBrowserCookies = cfg.allowBrowserCookies;
            geminiBaseUrl = cfg.geminiBaseUrl;
            braveApiKey = cfg.braveApiKey;
            exaApiKey = cfg.exaApiKey;
            geminiApiKey = cfg.geminiApiKey;
            cloudflareApiKey = cfg.cloudflareApiKey;
            tavilyApiKey = cfg.tavilyApiKey;
            parallelApiKey = cfg.parallelApiKey;
            perplexityApiKey = cfg.perplexityApiKey;
          }
          // cfg.extraSettings
        );
  };
}
