# features/dev/pi/plugins/pi-web-access/module.nix
# Web fetch & search capabilities plugin for Pi coding agent.
{
  config,
  lib,
  ...
}:
let
  cfg = config.my.features.dev.pi.plugins.web-access;
  piCfg = config.my.features.dev.pi;
in
{
  options.my.features.dev.pi.plugins.web-access = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable web fetch & search capabilities plugin.";
    };

    workflow = lib.mkOption {
      type = lib.types.enum [
        "auto-summary"
        "none"
        "summary-review"
      ];
      default = "auto-summary";
      description = "Search workflow mode: 'auto-summary' (auto-approved background summary, no UI), 'none' (raw results, no curator), 'summary-review' (interactive browser curator).";
    };

    autoOpenBrowser = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Automatically open browser when using curator mode.";
    };

    curatorTimeoutSeconds = lib.mkOption {
      type = lib.types.int;
      default = 20;
      description = "Idle timeout in seconds before the curator auto-submits.";
    };

    summaryModel = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Model used for auto-generating summary drafts in auto-summary/curator mode.";
    };

    maxInlineContentChars = lib.mkOption {
      type = lib.types.int;
      default = 30000;
      description = "Direct fetch_content and get_search_content slice character limit.";
    };

    searchRouting = lib.mkOption {
      type = lib.types.submodule {
        options = {
          providers = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Ordered list of search providers to attempt sequentially.";
          };
          fallbackOn = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [
              "transient"
              "quota"
              "network"
              "invalid-response"
            ];
            description = "Error types that trigger fallback to the next provider.";
          };
        };
      };
      default = { };
      description = "Search provider sequential fallback configuration.";
    };

    extraConfig = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Additional raw options merged into ~/.pi/web-search.json.";
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

          basePayload = {
            inherit (cfg)
              workflow
              autoOpenBrowser
              curatorTimeoutSeconds
              maxInlineContentChars
              ;
          }
          // lib.optionalAttrs (cfg.summaryModel != null) {
            inherit (cfg) summaryModel;
          }
          // lib.optionalAttrs (cfg.searchRouting.providers != [ ]) {
            searchRouting = {
              inherit (cfg.searchRouting) providers fallbackOn;
            };
          };

          webSearchPayload = lib.recursiveUpdate basePayload cfg.extraConfig;
        in
        {
          config = lib.mkIf userPiCfg.enable {
            home.file.".pi/web-search.json".text = builtins.toJSON webSearchPayload;
          };
        }
      )
    ];
  };
}
