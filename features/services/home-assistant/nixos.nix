{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.features.services.home-assistant;

  # The ingress terminates the public names on another host and reaches Home Assistant over the mesh
  # (`contracts/topology/lib/service-address.nix`): that overlay address is the peer Home Assistant
  # must trust to read X-Forwarded-For at all (see `http` below).
  serviceAddressLib = import ../../../contracts/topology/lib/service-address.nix { };
  ingressAddress = serviceAddressLib.serviceAddress {
    topology = config.my.topology;
    consumer = config.my.topology.hosts.${config.networking.hostName} or null;
    peer = config.my.topology.hosts.${config.my.topology.ingressHost};
  };
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

        http = {
          server_port = 8123;
          use_x_forwarded_for = true;
          # Loopback for the local ingress, plus the ingress host's overlay address: a request that
          # arrives with X-Forwarded-For from an untrusted peer is refused with 400 before Home
          # Assistant answers anything (measured 2026-10-10 - the whole public plane answered 400,
          # which is what made the MCP endpoint undiscoverable from the internet).
          trusted_proxies = [
            "127.0.0.1/32"
            "::1/128"
            "${ingressAddress}/32"
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
        # documented path; the trusted_proxies/use_x_forwarded_for settings are set above.
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
