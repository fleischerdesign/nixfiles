{ config, lib, pkgs, ... }:
let
  cfg = config.my.features.services.esphome;
in
{
  options.my.features.services.esphome.enable = lib.mkEnableOption "ESPHome Dashboard";

  config = lib.mkIf cfg.enable {
    services.esphome = {
      enable = true;
      port = 6052;
      openFirewall = true; # Öffnet automatisch Port 6052
    };

    # mDNS ist wichtig, damit ESPHome Geräte im Netzwerk findet
    networking.firewall.allowedUDPPorts = [ 5353 ];
  };
}
