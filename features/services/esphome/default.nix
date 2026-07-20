{
  config,
  lib,
  ...
}:
let
  cfg = config.my.features.services.esphome;
in
{
  options.my.features.services.esphome = {
    enable = lib.mkEnableOption "ESPHome Device Manager";
  };

  config = lib.mkIf cfg.enable {
    services.esphome = {
      enable = true;
      port = 6052;
    };

    my.endpoints.esphome-mdns = {
      host = config.networking.hostName;
      port = 5353;
      directAccess = {
        enable = true;
        protocol = "udp";
        interface = "all";
      };
      monitoring.http.enable = false;
    };

    my.endpoints.esphome = {
      host = config.networking.hostName;
      port = 6052;
    };
  };
}
