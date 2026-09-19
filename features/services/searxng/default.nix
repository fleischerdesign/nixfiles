# features/services/searxng/default.nix
# SearXNG privacy-respecting, self-hosted metasearch engine.
# Designed for autonomous AI agents (OpenClaw) and private user search.
#
# Security:
#   - Listens on 127.0.0.1 (Loopback) by default.
#   - Exposes Port on Tailscale firewall interface for cluster nodes.
#   - Optional Caddy reverse-proxy with Authentik forward-auth SSO for human browser use.
#   - JSON format enabled for machine API search requests.
{
  config,
  lib,
  ...
}:
let
  cfg = config.my.features.services.searxng;
in
{
  options.my.features.services.searxng = {
    enable = lib.mkEnableOption "SearXNG metasearch engine";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8888;
      description = "Internal port SearXNG listens on.";
    };

    bindAddress = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Address SearXNG binds to (0.0.0.0 enables direct access via Tailscale and loopback; external ports are blocked by firewall).";
    };

    secretKeySecret = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "services/apps/searxng_secret_key";
      description = "SOPS secret containing the 32-byte secret key for SearXNG.";
    };

    domain = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "search.${config.my.topology.domain}";
      description = "Public or Tailscale domain for SearXNG (derived; Naming spec §3).";
    };

    auth = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Protect web UI behind Authentik forward-auth.";
    };

    openTailscaleFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Allow direct access to SearXNG port over Tailscale interface.";
    };

    enableJsonApi = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable JSON output format for API clients like OpenClaw.";
    };

    extraSettings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Arbitrary settings merged into services.searx.settings.";
    };
  };

  config = lib.mkIf cfg.enable {
    # SOPS secret declaration
    sops.secrets = lib.mkIf (cfg.secretKeySecret != null) {
      "${cfg.secretKeySecret}" = {
        owner = "searx";
        group = "searx";
        mode = "0400";
      };
    };

    # Systemd environment file rendering for secret substitution
    sops.templates = lib.mkIf (cfg.secretKeySecret != null) {
      "searxng_env" = {
        owner = "searx";
        group = "searx";
        mode = "0400";
        restartUnits = [ "searx.service" ];
        content = ''
          SEARXNG_SECRET=${config.sops.placeholder.${cfg.secretKeySecret}}
        '';
      };
    };

    # Upstream NixOS Searx service
    services.searx = {
      enable = true;
      environmentFile = lib.mkIf (cfg.secretKeySecret != null) config.sops.templates."searxng_env".path;

      settings = lib.recursiveUpdate {
        general = {
          instance_name = "Ancoris Search";
          donation_url = false;
          contact_url = false;
          enable_metrics = false;
        };

        server = {
          port = cfg.port;
          bind_address = cfg.bindAddress;
          secret_key = "@SEARXNG_SECRET@";
          base_url = lib.optionalString (cfg.domain != null) "https://${cfg.domain}/";
          image_proxy = true;
        };

        search = {
          safe_search = 0;
          autocomplete = "duckduckgo";
          formats = [ "html" ] ++ lib.optional cfg.enableJsonApi "json";
        };

        # Engine selection: VPS friendly (avoid Google IP rate-limits/captchas)
        engines = [
          {
            name = "google";
            disabled = true;
          }
          {
            name = "google images";
            disabled = true;
          }
          {
            name = "google news";
            disabled = true;
          }
          {
            name = "duckduckgo";
            engine = "duckduckgo";
            disabled = false;
          }
          {
            name = "bing";
            engine = "bing";
            disabled = false;
          }
          {
            name = "brave";
            engine = "brave";
            disabled = false;
          }
          {
            name = "qwant";
            engine = "qwant";
            disabled = false;
          }
          {
            name = "startpage";
            engine = "startpage";
            disabled = false;
          }
          {
            name = "wikipedia";
            engine = "wikipedia";
            disabled = false;
          }
          {
            name = "wikidata";
            engine = "wikidata";
            disabled = false;
          }
          {
            name = "github";
            engine = "github";
            disabled = false;
          }
          {
            name = "arxiv";
            engine = "arxiv";
            disabled = false;
          }
        ];
      } cfg.extraSettings;
    };

    # Ensure searx restarts on settings changes
    systemd.services.searx-init.restartTriggers = [
      config.services.searx.settingsPath
    ];

    systemd.services.searx.restartTriggers = [
      config.services.searx.settingsPath
    ];

    # Register into central service catalog
    my.contracts.provides.searxng = {
      endpoints.web = {
        port = cfg.port;
        protocol = "tcp";
        scope = if cfg.domain != null then "public" else "isolated";
        auth = if cfg.auth then "authentik" else "none";
        subdomain = "search";
        directAccess = {
          enable = cfg.openTailscaleFirewall;
          protocol = "tcp";
          interface = "tailscale";
        };
        dashboard = {
          show = true;
          displayName = "SearXNG Search";
          category = "Observability & Tools";
          icon = "searxng";
        };
      };
    };
  };
}
