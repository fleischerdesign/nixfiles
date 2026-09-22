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
      ]
      # The textfile collector publishes what a oneshot job cannot expose itself. `authentik-drift-report`
      # writes its finding count to that directory, so a divergence between the declarations and the
      # database becomes a Prometheus series instead of a journal line nobody reads (identity.md §11.6).
      # Both the collector and its directory are added only where that server runs.
      ++ lib.optional config.my.features.services.authentik.server.enable "textfile";
      extraFlags = lib.optionals config.my.features.services.authentik.server.enable [
        "--collector.textfile.directory=/var/lib/authentik-metrics"
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
