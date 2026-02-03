{ config, lib, pkgs, ... }:

let
  cfg = config.my.features.services.monitoring.grafana;
in
{
  options.my.features.services.monitoring.grafana = {
    enable = lib.mkEnableOption "Grafana Dashboard";
  };

  config = lib.mkIf cfg.enable {
    services.grafana = {
      enable = true;
      settings = {
        server = {
          http_addr = "127.0.0.1";
          http_port = 3000;
          domain = "grafana.mky.ancoris.ovh";
          root_url = "https://grafana.mky.ancoris.ovh";
        };
      };

      provisioning = {
        datasources.settings.datasources = [
          {
            name = "Prometheus";
            type = "prometheus";
            url = "http://localhost:9090";
            isDefault = true;
          }
          {
            name = "Loki";
            type = "loki";
            url = "http://localhost:3100";
          }
        ];
      };
    };

    # Reverse Proxy
    my.features.services.caddy.exposedServices = {
      "grafana" = {
        port = 3000;
        subdomain = "grafana";
      };
    };
  };
}
