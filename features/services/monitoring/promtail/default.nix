{ config, lib, pkgs, ... }:

let
  cfg = config.my.features.services.monitoring.promtail;
in
{
  options.my.features.services.monitoring.promtail = {
    enable = lib.mkEnableOption "Promtail Log Agent";
    lokiHost = lib.mkOption {
      type = lib.types.str;
      description = "The hostname or IP of the Loki server to push logs to.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.promtail = {
      enable = true;
      configuration = {
        server = {
          http_listen_port = 9080;
          grpc_listen_port = 0;
        };
        clients = [{ url = "http://${cfg.lokiHost}:3100/loki/api/v1/push"; }];
        scrape_configs = [
          {
            job_name = "journal";
            journal = {
              max_age = "12h";
              labels = {
                job = "systemd-journal";
                host = config.networking.hostName;
              };
            };
            relabel_configs = [{
              source_labels = [ "__journal__systemd_unit" ];
              target_label = "unit";
            }];
          }
          {
            job_name = "caddy";
            static_configs = [{
              targets = [ "localhost" ];
              labels = {
                job = "caddy-access";
                host = config.networking.hostName;
                __path__ = "/var/log/caddy/*.log";
              };
            }];
          }
        ];
      };
    };

    # Grant journal and log access to promtail
    users.users.promtail = {
      extraGroups = [ "systemd-journal" "caddy" ];
    };
  };
}
