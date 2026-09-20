{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.features.services.home-assistant;
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
      ];
      config = {
        # This generates the configuration.yaml
        default_config = { };

        # Enable UI editing
        "automation ui" = "!include automations.yaml";
        "script ui" = "!include scripts.yaml";
        "scene ui" = "!include scenes.yaml";
        rest_command = "!include ${config.sops.templates."hass-rest-commands.yaml".path}";

        http = {
          server_port = 8123;
          use_x_forwarded_for = true;
          trusted_proxies = [
            "127.0.0.1"
            "::1"
          ];
        };
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
      endpoints.web = {
        port = 8123;
        protocol = "tcp";
        # Public per docs/naming.md §9.4 (decision recorded). Scope and auth must move together.
        scope = "public";
        # Home Assistant enforces its own authentication. Its official documentation
        # (integrations/http, Reverse proxies) defines the trusted-proxy settings but NO set of
        # paths an external SSO proxy may bypass, and a forward-auth layer in front of HA breaks
        # the companion app and the WebSocket API. Direct exposure with HA's own auth is the
        # documented path; the trusted_proxies/use_x_forwarded_for settings are set above.
        auth = "none";
        publicExempt = "Home Assistant enforces its own authentication (documented for direct internet exposure); an external forward-auth proxy breaks the companion app and the WebSocket API";
        subdomain = "hass";
        directAccess = {
          enable = true;
          protocol = "tcp";
          interface = "all";
        };
        dashboard = {
          show = true;
          displayName = "Home Assistant";
          category = "Smart Home";
          icon = "home-assistant";
        };
      };
      storage = {
        stateDirs = [ "/var/lib/hass" ];
      };
    };
  };
}
