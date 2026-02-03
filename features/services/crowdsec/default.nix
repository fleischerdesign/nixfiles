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

      # Wir setzen den Port auf 8085, müssen aber die API-Struktur erhalten
      settings = {
        general = {
          api = {
            client = {
              credentials_path = "/etc/crowdsec/local_api_credentials.yaml"; # Wichtig für cscli
            };
            server = {
              listen_uri = "127.0.0.1:8085";
              enable = true; # Wichtig, damit cscli weiß, dass LAPI aktiv ist
            };
          };
          # Logs, DB etc. werden meist aus Defaults gemerged oder sind nicht kritisch für den Start
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
    
    # Secret definition - restart units if secret changes
    sops.secrets.crowdsec_bouncer_api_key = { 
        # Falls der Bouncer Service DynamicUser nutzt, brauchen wir evtl. keine Owner Anpassung,
        # da systemd LoadCredential das regelt.
        # Aber sicherheitshalber triggern wir den Restart.
        restartUnits = [ "crowdsec-firewall-bouncer.service" ];
    };
  };
}