{ config, lib, pkgs, ... }:
let
  cfg = config.services.crowdsec;
in
{
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
  users.users.crowdsec.extraGroups = [ "systemd-journal" ];

  services.crowdsec-firewall-bouncer = {
    enable = true;
    settings = {
      api_url = "http://127.0.0.1:8085/";
      api_key_file = config.sops.secrets.crowdsec_bouncer_api_key.path;
    };
  };
  
  sops.secrets.crowdsec_bouncer_api_key = { 
      restartUnits = [ "crowdsec-firewall-bouncer.service" ];
  };
}
