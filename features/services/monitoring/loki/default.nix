{
  config,
  lib,
  ...
}:

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

        schema_config.configs = [
          {
            from = "2020-10-24";
            store = "tsdb";
            object_store = "filesystem";
            schema = "v13";
            index.prefix = "index_";
            index.period = "24h";
          }
        ];
      };
    };

    my.contracts.provides.loki = {
      # Loki's gRPC face: the log pipeline on this host talks to it, nobody else.
      endpoints.grpc = {
        port = 9095;
        protocol = "tcp";
        scope = "isolated";
        directAccess = {
          enable = true;
          interface = "local";
          protocol = "tcp";
        };
      };
      endpoints.web = {
        port = 3100;
        protocol = "tcp";
        scope = "internal";
        # Logs are shipped here from every other host, so the port belongs on the mesh.
        directAccess = {
          enable = true;
          interface = "wireguard";
          protocol = "tcp";
        };
        monitoring = {
          http.enable = false;
          tcp.enable = true;
          tcp.group = "Observability";
        };
      };
      storage = {
        stateDirs = [ "/var/lib/loki" ];
      };
    };
  };
}
