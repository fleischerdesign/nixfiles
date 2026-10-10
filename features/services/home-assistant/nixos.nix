{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.features.services.home-assistant;

  # The ingress terminates the public names on another host and reaches Home Assistant over the mesh,
  # so Home Assistant has to accept X-Forwarded-For from that host - and answers 400 to everything
  # else. The trust is not declarable from here: Home Assistant 2026.8 migrated the `http` integration
  # out of YAML, ignores an `http:` block ever after and drops YAML support in 2027.2. The value lives
  # in Home Assistant's own store (`/var/lib/hass/.storage/http`, `stable` slot) and is set under
  # Settings - System - Network, with the ingress host's overlay address in `trusted_proxies`; see
  # `docs/architecture.md` 6.1.
in
{
  options.my.features.services.home-assistant = {
    enable = lib.mkEnableOption "Home Assistant";
  };

  config = lib.mkIf cfg.enable {
    sops.secrets."services/home/hass_now_api_token" = {
      owner = "hass";
    };

    sops.templates."hass-rest-commands.yaml" = {
      owner = "hass";
      content = ''
        now_school:
          url: "https://fleischer.design/api/now"
          method: POST
          headers:
            Authorization: "Bearer ${config.sops.placeholder."services/home/hass_now_api_token"}"
          content_type: "application/json"
          payload: >
            {
              "de": "Gerade am lernen",
              "en": "Now learning",
              "icon": "mage:book-text"
            }
        now_home_programming:
          url: "https://fleischer.design/api/now"
          method: POST
          headers:
            Authorization: "Bearer ${config.sops.placeholder."services/home/hass_now_api_token"}"
          content_type: "application/json"
          payload: >
            {
              "de": "Gerade am coden",
              "en": "Now programming",
              "icon": "mage:robot-uwu"
            }
        now_sport:
          url: "https://fleischer.design/api/now"
          method: "POST"
          headers:
            Authorization: "Bearer ${config.sops.placeholder."services/home/hass_now_api_token"}"
          content_type: "application/json"
          payload: >
            {
              "de": "Gerade am Sport treiben",
              "en": "Now doing sports",
              "icon": "mage:zap"
            }
      '';
    };

    services.home-assistant = {
      enable = true;

      # PKCE S256 backport for the MCP server's OAuth flow. Home Assistant advertises and implements
      # PKCE (RFC 7636) only from 2026.10.0 on (home-assistant/core#181957), and ChatGPT refuses to
      # create a connector against an instance whose /.well-known/oauth-authorization-server omits
      # `"code_challenge_methods_supported": ["S256"]`. The patches carry that upstream commit plus
      # its hardening follow-up on the release nixpkgs pins today; they drop out of their own accord
      # once nixpkgs ships 2026.10.x, with a warning that names the files to delete.
      package =
        if lib.versionOlder pkgs.home-assistant.version "2026.10" then
          pkgs.home-assistant.overrideAttrs (old: {
            patches = (old.patches or [ ]) ++ [
              ./patches/pkce-s256.patch
              ./patches/pkce-hardening.patch
            ];
          })
        else
          lib.warn "home-assistant ${pkgs.home-assistant.version} ships PKCE S256: delete features/services/home-assistant/patches/pkce-*.patch and this override" pkgs.home-assistant;

      customComponents = [
        pkgs.home-assistant-custom-components.moonraker
      ];
      extraComponents = [
        # Pre-install common python dependencies for integrations
        "esphome"
        "met"
        "radio_browser"
        "mobile_app"
        "zha" # Zigbee Home Automation
        "cast" # Google Cast / Chromecast
        "ipp" # Internet Printing Protocol (Printers)
        "androidtv_remote" # Fix for ModuleNotFoundError: No module named 'androidtvremote2'
        "mqtt"
        "google_translate" # gTTS
        # Model Context Protocol server. The integration itself is a config entry (no YAML
        # setup); this only bundles its Python dependencies so it can be added in the UI.
        "mcp_server"
      ];
      config = {
        # This generates the configuration.yaml
        default_config = { };

        # MCP clients discover the authorization server over the public name; without an
        # instance URL the discovery documents answer relative URLs. The name is projected,
        # not written: the publication already owns https://hass.<domain>.
        homeassistant = {
          external_url = config.my.contracts.provides.home-assistant.publications.web.publicUrl;
          internal_url = config.my.contracts.provides.home-assistant.publications.web.publicUrl;
        };

        # Enable UI editing
        "automation ui" = "!include automations.yaml";
        "script ui" = "!include scripts.yaml";
        "scene ui" = "!include scenes.yaml";
        rest_command = "!include ${config.sops.templates."hass-rest-commands.yaml".path}";
      };
    };

    # Firewall port is auto-managed via endpoints.directAccess.enable

    # Allow Home Assistant to access Zigbee USB sticks
    users.users.hass = {
      extraGroups = [
        "dialout"
        "tty"
      ];
    };

    # mDNS for device discovery (Cast, IPP, ESPHome)
    services.avahi = {
      enable = true;
      nssmdns4 = true;
      publish = {
        enable = true;
        addresses = true;
        userServices = true;
      };
    };

    my.contracts.provides.home-assistant = {
      publications."web" = {
        scope = "public";
        endpoint = "web";
        auth = "none";
        publicExempt = "Home Assistant enforces its own authentication (documented for direct internet exposure); an external forward-auth proxy breaks the companion app and the WebSocket API";
        subdomain = "hass";
      };
      presentation.tiles."web" = {
        endpoint = "web";
        description = {
          de = "Hausautomation und Sensoren.";
          en = "Home automation and sensors.";
        };
        show = true;
        displayName = "Home Assistant";
        category = "Smart Home";
        icon = "home-assistant";
      };
      telemetry.probes."web-http".endpoint = "web";
      telemetry.probes."web-http".kind = "http";
      endpoints.web = {
        port = 8123;
        protocol = "tcp";
        # Public per docs/naming.md §9.4 (decision recorded). Scope and auth must move together.
        # Home Assistant enforces its own authentication. Its official documentation
        # (integrations/http, Reverse proxies) defines the trusted-proxy settings but NO set of
        # paths an external SSO proxy may bypass, and a forward-auth layer in front of HA breaks
        # the companion app and the WebSocket API. Direct exposure with HA's own auth is the
        # documented path; the trusted-proxy settings are Home Assistant settings, not a module
        # option (see the module's `let` block and docs/architecture.md 6.1).
        directAccess = {
          enable = true;
          protocol = "tcp";
          interface = "all";
        };

      };
      storage = {
        stateDirs = [ "/var/lib/hass" ];
      };
    };
  };
}
