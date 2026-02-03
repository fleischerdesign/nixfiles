{ config, lib, pkgs, ... }:
let
  cfg = config.my.features.services.home-assistant;
in
{
  options.my.features.services.home-assistant = {
    enable = lib.mkEnableOption "Home Assistant";
    expose = {
      enable = lib.mkEnableOption "Expose via Caddy";
      subdomain = lib.mkOption { type = lib.types.str; default = "hass"; };
      auth = lib.mkEnableOption "Protect with Authentik";
    };
  };

  config = lib.mkIf cfg.enable {
    services.home-assistant = {
      enable = true;
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
        default_config = {};
        
        # Enable UI editing
        "automation ui" = "!include automations.yaml";
        "script ui" = "!include scripts.yaml";
        "scene ui" = "!include scenes.yaml";

        http = {
          server_port = 8123;
          use_x_forwarded_for = true;
          trusted_proxies = [ "127.0.0.1" "::1" ];
        };
      };
    };

    # Open firewall port
    networking.firewall.allowedTCPPorts = [ 8123 ];

    # Allow Home Assistant to access Zigbee USB sticks
    users.users.hass = {
      extraGroups = [ "dialout" "tty" ];
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

    # Register with Caddy Feature
    my.features.services.caddy.exposedServices = lib.mkIf cfg.expose.enable {
      "home-assistant" = {
        port = 8123;
        auth = cfg.expose.auth;
        subdomain = cfg.expose.subdomain;
      };
    };
  };
}