# features/services/searxng/nixos.nix
# SearXNG privacy-respecting, self-hosted metasearch engine.
# Designed for autonomous AI agents and private user search.
#
# Security:
#   - Listens on 127.0.0.1 (Loopback) by default.
#   - Exposes the port on the WireGuard mesh interface for cluster nodes.
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
      description = "Address SearXNG binds to (0.0.0.0 enables direct access over the mesh and loopback; external ports are blocked by firewall).";
    };

    secretKeySecret = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "services/apps/searxng_secret_key";
      description = "SOPS secret containing the 32-byte secret key for SearXNG.";
    };

    public = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Publish this service on the public ingress. It replaces the switch that the old `domain`
        option hid: that option had a non-null default, so "a domain is set" was always true and
        the isolated branch could never be reached.
      '';
    };

    auth = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Protect web UI behind Authentik forward-auth.";
    };

    openMeshFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Allow direct access to the SearXNG port over the WireGuard mesh interface.";
    };

    enableJsonApi = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable JSON output format for API clients such as autonomous agents.";
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
          base_url = lib.optionalString (
            config.my.contracts.provides.searxng.publications.web.canonicalDomain != null
          ) "https://${config.my.contracts.provides.searxng.publications.web.canonicalDomain}/";
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

    # Register into central service catalog. The name is not declared here: the endpoint's
    # `subdomain` plus the topology's root domain derive it, and the application reads the derived
    # value back (one rule, one place).
    my.contracts.provides.searxng = {
      # Whether the service is published is now the existence of a publication: no publication, no
      # DNS name and no ingress. The endpoint below is only a listener.
      publications = lib.optionalAttrs cfg.public {
        web = {
          scope = "public";
          endpoint = "web";
          auth = if cfg.auth then "authentik" else "none";
          accessGroups = [ "family" ];
          subdomain = "search";
        };
      };
      presentation.tiles."web" = {
        endpoint = "web";
        description = {
          de = "Metasuche ohne Tracking.";
          en = "Metasearch without tracking.";
        };
        show = true;
        displayName = "SearXNG Search";
        category = "Observability & Tools";
        icon = "searxng";
      };
      telemetry.probes."web-http".endpoint = "web";
      telemetry.probes."web-http".kind = "http";
      endpoints.web = {
        port = cfg.port;
        protocol = "tcp";
        # Whether the service is published is the existence of the publication above, not a second
        # switch on the listener.
        directAccess = {
          enable = cfg.openMeshFirewall;
          protocol = "tcp";
          interface = "wireguard";
        };

      };
    };
  };
}
