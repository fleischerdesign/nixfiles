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

    my.contracts.provides.node-exporter = {
      endpoints.metrics = {
        port = 9100;
        protocol = "tcp";
        scope = "internal";
        # Scraped from another host: the collector lives on the ingress, this exporter does not, so the
        # port has to be reachable over the mesh. Declared here rather than trusted into existence.
        directAccess = {
          enable = true;
          interface = "wireguard";
          protocol = "tcp";
        };
        monitoring = {
          http.enable = false;
          tcp.enable = true;
          tcp.group = "Infrastructure";
          scrape.enable = true;
          scrape.port = 9100;
        };
      };
    };
  };
}
