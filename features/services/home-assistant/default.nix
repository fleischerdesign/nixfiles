{ config, lib, pkgs, ... }:
let
  cfg = config.my.features.services.home-assistant;
in
{
  options.my.features.services.home-assistant.enable = lib.mkEnableOption "Home Assistant";

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
      ];
      config = {
        # This generates the configuration.yaml
        default_config = {};
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
  };
}
