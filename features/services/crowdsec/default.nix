{ config, lib, pkgs, ... }:
let
  cfg = config.my.features.services.crowdsec;
  isMaster = cfg.role == "master";
  # Mackaye's Tailscale IP
  masterIP = "100.120.39.68";
in
{
  options.my.features.services.crowdsec = {
    enable = lib.mkEnableOption "CrowdSec IPS";
    role = lib.mkOption {
      type = lib.types.enum [ "master" "agent" ];
      default = "agent";
      description = "Role of this host: master (LAPI server) or agent (client).";
    };
  };

  config = lib.mkIf cfg.enable {
    services.crowdsec = {
      enable = true;
      
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
        # Master-spezifische Server-Einstellungen
        general = lib.mkIf isMaster {
          api.server = {
            listen_uri = "0.0.0.0:8085"; # Auf allen Interfaces lauschen (Tailscale!)
            enable = true;
          };
          prometheus = {
            enabled = true;
            level = "full";
            listen_addr = "0.0.0.0";
            listen_port = 6060;
          };
        };

        # Agent-Konfiguration: Wo ist der Master?
        lapi.credentialsFile = if isMaster 
          then "/etc/crowdsec/local_api_credentials.yaml"
          else config.sops.secrets.crowdsec_agent_credentials.path;
      };
    };

    # Firewall-Bouncer: Verbindet sich immer zur LAPI (lokal oder remote)
    services.crowdsec-firewall-bouncer = {
      enable = true;
      settings = {
        api_url = "http://${masterIP}:8085/";
        api_key_file = config.sops.secrets.crowdsec_bouncer_key.path;
      };
    };

    # Berechtigungen & User
    users.users.crowdsec.extraGroups = [ "systemd-journal" "caddy" ];
    systemd.services.crowdsec-firewall-bouncer.serviceConfig.DynamicUser = lib.mkForce false;

    # Secrets
    sops.secrets.crowdsec_bouncer_key = {
      owner = "root";
      restartUnits = [ "crowdsec-firewall-bouncer.service" ];
    };

    # Nur Agents brauchen die Credentials für den Master
    sops.secrets.crowdsec_agent_credentials = lib.mkIf (!isMaster) {
      owner = "crowdsec";
      restartUnits = [ "crowdsec.service" ];
    };
  };
}