{ config, lib, pkgs, ... }:

let
  cfg = config.my.features.services.monitoring.loki;
in
{
  options.my.features.services.monitoring.loki = {
    enable = lib.mkEnableOption "Loki Log Server";
  };

  config = lib.mkIf cfg.enable {
    services.loki = {
      enable = true;
      configuration = {
        auth_enabled = false;
        server.http_listen_port = 3100;
        server.http_listen_address = "0.0.0.0"; # Allow remote log shipping via Tailscale
        
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
  };
}