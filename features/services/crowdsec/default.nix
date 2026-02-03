{ config, lib, pkgs, ... }:
let
  cfg = config.my.features.services.crowdsec;
in
{
  options.my.features.services.crowdsec = {
    enable = lib.mkEnableOption "CrowdSec IPS";
  };

  config = lib.mkIf cfg.enable {
    services.crowdsec = {
      enable = true;

      localConfig.acquisitions = [
        {
          filenames = [ "/var/lib/caddy/access-*.log" ];
          labels.type = "caddy";
        }
        {
          source = "journalctl";
          journalctl_filter = [ "_SYSTEMD_UNIT=sshd.service" ];
          labels.type = "syslog";
        }
      ];

      settings = {
        general = {
          api = {
            server = {
              listen_uri = "127.0.0.1:8085";
            };
          };
        };
      };
    };

    # Manually grant journal access to crowdsec
    users.users.crowdsec.extraGroups = [ "systemd-journal" ];

    services.crowdsec-firewall-bouncer = {
      enable = true;
      settings = {
        api_url = "http://127.0.0.1:8085/";
        api_key_file = config.sops.secrets.crowdsec_bouncer_api_key.path;
      };
    };
    
    # Nur ein Secret nötig
    sops.secrets.crowdsec_bouncer_api_key = { };
  };
}
