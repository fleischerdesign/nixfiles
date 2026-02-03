{ config, lib, pkgs, ... }:

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
      enabledCollectors = [ "systemd" "processes" ];
      port = 9100;
      openFirewall = true;
    };
  };
}