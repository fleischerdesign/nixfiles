{ config, lib, pkgs, ... }:

let
  cfg = config.my.features.services.monitoring.loki;
in
{
  options.my.features.services.monitoring.loki = {
    enable = lib.mkEnableOption "Loki and Promtail";
  };

  config = lib.mkIf cfg.enable {
    # Loki Server
    services.loki = {
      enable = true;
      configuration = {
        auth_enabled = false;
        server.http_listen_port = 3100;
        
        common.instance_addr = "127.0.0.1";
        common.path_prefix = "/var/lib/loki";
        common.storage.filesystem = {
          chunks_directory = "/var/lib/loki/chunks";
          rules_directory = "/var/lib/loki/rules";
        };
        common.replication_factor = 1;
        common.ring.instance_addr = "127.0.0.1";
        common.ring.kvstore.store = "inmemory";

        schema_config.configs = [{
          from = "2020-10-24";
          store = "tsdb";
          object_store = "filesystem";
          schema = "v13";
          index.prefix = "index_";
          index.period = "24h";
        }];
      };
    };

    # Promtail (Local Log Shipper)
    services.promtail = {
      enable = true;
      configuration = {
        server = {
          http_listen_port = 9080;
          grpc_listen_port = 0;
        };
        clients = [{ url = "http://127.0.0.1:3100/loki/api/v1/push"; }];
        scrape_configs = [{
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
        }];
      };
    };
  };
}
