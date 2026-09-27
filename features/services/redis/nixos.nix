{
  config,
  lib,
  ...
}:
let
  cfg = config.my.features.services.redis;
in
{
  options.my.features.services.redis = {
    enable = lib.mkEnableOption "Central Redis Server";
  };

  config = lib.mkIf cfg.enable {
    # Central 'system' instance on default port 6379
    services.redis.servers."system" = {
      enable = true;
      port = 6379;
      bind = "127.0.0.1";
      # Optional: Persistence configuration if needed
      appendOnly = true;
    };

    my.contracts.provides.redis = {
      telemetry.probes."server-tcp".endpoint = "server";
      telemetry.probes."server-tcp".kind = "tcp";
      endpoints.server = {
        port = 6379;
        protocol = "tcp";
        applicationProtocol = "redis";
      };
      storage = {
        stateDirs = [ "/var/lib/redis-system" ];
      };
    };
  };
}
