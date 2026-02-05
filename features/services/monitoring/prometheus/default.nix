{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.features.services.monitoring.prometheus;
  strummerTailscaleIp = config.my.features.system.networking.topology.strummer.tailscaleIp;
in
{
  options.my.features.services.monitoring.prometheus = {
    enable = lib.mkEnableOption "Prometheus Server";
  };

  config = lib.mkIf cfg.enable {
    services.prometheus = {
      enable = true;
      port = 9090;

      scrapeConfigs = [
        {
          job_name = "prometheus";
          static_configs = [ { targets = [ "localhost:9090" ]; } ];
        }
        {
          job_name = "node_mackaye";
          static_configs = [ { targets = [ "localhost:9100" ]; } ];
        }
        {
          job_name = "node_strummer";
          static_configs = [ { targets = [ "${strummerTailscaleIp}:9100" ]; } ];
        }
        {
          job_name = "crowdsec_mackaye";
          static_configs = [ { targets = [ "localhost:6060" ]; } ];
        }
        {
          job_name = "crowdsec_strummer";
          static_configs = [ { targets = [ "${strummerTailscaleIp}:6060" ]; } ];
        }
        {
          job_name = "authentik";
          static_configs = [ { targets = [ "localhost:9300" ]; } ];
        }
        {
          job_name = "blocky_strummer";
          static_configs = [ { targets = [ "${strummerTailscaleIp}:4000" ]; } ];
        }
      ];
    };
  };
}
