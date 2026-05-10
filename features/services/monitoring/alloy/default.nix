{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.features.services.monitoring.alloy;
in
{
  options.my.features.services.monitoring.alloy = {
    enable = lib.mkEnableOption "Alloy Log Agent";
    lokiHost = lib.mkOption {
      type = lib.types.str;
      description = "The hostname or IP of the Loki server to push logs to.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.alloy = {
      enable = true;
      configPath = "/etc/alloy/config.alloy";
    };

    environment.etc."alloy/config.alloy".text = ''
      loki.source.journal "read_journal" {
        forward_to = [loki.write.loki_service.receiver]
        labels = {
          job = "systemd-journal",
          host = "${config.networking.hostName}",
        }
      }

      loki.source.file "caddy" {
        targets = [
          { __path__ = "/var/log/caddy/*.log", host = "${config.networking.hostName}", job = "caddy-access" },
        ]
        forward_to = [loki.write.loki_service.receiver]
      }

      loki.write "loki_service" {
        endpoint {
          url = "http://${cfg.lokiHost}:3100/loki/api/v1/push"
        }
      }
    '';

    # Grant journal and log access to alloy
    users.users.alloy = {
      isSystemUser = true;
      group = "alloy";
      extraGroups = [
        "systemd-journal"
        "caddy"
      ];
    };
    users.groups.alloy = { };
  };
}
