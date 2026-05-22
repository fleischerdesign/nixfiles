{
  config,
  lib,
  ...
}:

let
  cfg = config.my.features.services.monitoring.node-exporter;
in
{
  options.my.features.services.monitoring.node-exporter = {
    enable = lib.mkEnableOption "Prometheus Node Exporter";
  };

  config = lib.mkIf cfg.enable {
    services.prometheus.exporters.node = {
      enable = true;
      enabledCollectors = [
        "systemd"
        "processes"
      ];
      port = 9100;
    };

    my.endpoints.node-exporter = {
      host = config.networking.hostName;
      port = 9100;
      monitoring = {
        http.enable = false;
        tcp.enable = true;
        tcp.group = "Infrastructure";
        scrape.enable = true;
        scrape.port = 9100;
      };
    };
  };
}
