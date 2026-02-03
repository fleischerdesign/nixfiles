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
        
        # Install required collections
        hub.collections = [
          "crowdsecurity/linux"
          "crowdsecurity/caddy"
        ];
  
        localConfig.acquisitions = [
            {

              filenames = [ "/var/log/caddy/access-*.log" ];

              labels.type = "caddy";

            }

            {

              source = "journalctl";

      
          journalctl_filter = [ "_SYSTEMD_UNIT=sshd.service" ];
          labels.type = "syslog";
        }
      ];

      settings = {
        # Konfiguriere Credentials Pfad über das Modul-Interface
        lapi.credentialsFile = "/etc/crowdsec/local_api_credentials.yaml";

        # Zwinge den Port auf 8085 via general settings override
        general = {
          api = {
            server = {
              listen_uri = lib.mkForce "127.0.0.1:8085";
              enable = true; 
            };
          };
        };
      };
    };

    # Manually grant journal access to crowdsec
    users.users.crowdsec.extraGroups = [ "systemd-journal" "caddy" ];

    services.crowdsec-firewall-bouncer = {
      enable = true;
      settings = {
        api_url = "http://127.0.0.1:8085/";
        api_key_file = config.sops.secrets.crowdsec_bouncer_api_key.path;
      };
    };

    # Fix permission issues with sops secrets by disabling DynamicUser
    systemd.services.crowdsec-firewall-bouncer.serviceConfig.DynamicUser = lib.mkForce false;
    
    # Secret definition - restart units if secret changes
    sops.secrets.crowdsec_bouncer_api_key = {
        restartUnits = [ "crowdsec-firewall-bouncer.service" ];
    };
  };
}
