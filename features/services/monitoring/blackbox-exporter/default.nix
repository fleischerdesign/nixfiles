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
      configFile = pkgs.writeText "blackbox.yml" (
        builtins.toJSON {
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
            icmp = {
              prober = "icmp";
              timeout = "5s";
              icmp = {
                preferred_ip_protocol = "ip4";
              };
            };
          };
        }
      );
    };

    my.contracts.provides.blackbox-exporter = {
      endpoints.web = {
        port = 9115;
        protocol = "tcp";
        scope = "internal";
        # Probed from the collector on another host, so the port belongs on the mesh.
        directAccess = {
          enable = true;
          interface = "wireguard";
          protocol = "tcp";
        };
        monitoring = {
          tcp.enable = true;
          tcp.group = "Infrastructure";
        };
      };
    };
  };
}
