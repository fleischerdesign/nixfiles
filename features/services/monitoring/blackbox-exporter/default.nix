{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.features.services.monitoring.blackbox-exporter;
in
{
  options.my.features.services.monitoring.blackbox-exporter = {
    enable = lib.mkEnableOption "Blackbox Exporter for HTTP/TCP probing";
  };

  config = lib.mkIf cfg.enable {
    services.prometheus.exporters.blackbox = {
      enable = true;
      port = 9115;
      configFile = pkgs.writeText "blackbox.yml" (builtins.toJSON {
        modules = {
          http_2xx = {
            prober = "http";
            timeout = "10s";
            http = {
              valid_status_codes = [ ];
              no_follow_redirects = false;
              preferred_ip_protocol = "ip4";
            };
          };
          tcp_connect = {
            prober = "tcp";
            timeout = "5s";
          };
        };
      });
    };

    my.registry.blackbox-exporter = {
      host = config.networking.hostName;
      port = 9115;
      monitoring.tcp.enable = true;
      monitoring.tcp.group = "Infrastructure";
    };
  };
}
