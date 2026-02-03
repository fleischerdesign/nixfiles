{ config, lib, pkgs, ... }:
let
  cfg = config.my.features.services.authentik.outpost.ldap;
in
{
  options.my.features.services.authentik.outpost.ldap.enable = lib.mkEnableOption "Authentik LDAP Outpost";

  config = lib.mkIf cfg.enable {
    # Secrets Setup
    sops.secrets."authentik_outpost_ldap_token" = {
      owner = "authentik-outpost-ldap";
      restartUnits = [ "authentik-outpost-ldap.service" ];
    };

    # Template for env vars
    sops.templates."authentik-outpost-ldap.env".content = ''
      AUTHENTIK_TOKEN=${config.sops.placeholder."authentik_outpost_ldap_token"}
    '';

    # Create system user
    users.users.authentik-outpost-ldap = {
      isSystemUser = true;
      group = "authentik-outpost-ldap";
    };
    users.groups.authentik-outpost-ldap = {};

    # Systemd Service
    systemd.services.authentik-outpost-ldap = {
      description = "Authentik LDAP Outpost";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      
      serviceConfig = {
        ExecStart = lib.getExe pkgs.authentik-outposts.ldap;
        EnvironmentFile = config.sops.templates."authentik-outpost-ldap.env".path;
        
        # Configure connection to Authentik Core via Tailscale
        Environment = [
            "AUTHENTIK_HOST=http://100.120.39.68:9005"
            "AUTHENTIK_INSECURE_SKIP_VERIFY=true"
        ];
        
        Restart = "always";
        User = "authentik-outpost-ldap";
        Group = "authentik-outpost-ldap";
        StateDirectory = "authentik-outpost-ldap"; 
        
        # Allow binding to privileged ports (389, 636)
        AmbientCapabilities = "CAP_NET_BIND_SERVICE";
        CapabilityBoundingSet = "CAP_NET_BIND_SERVICE";
      };
    };

    # Open Firewall Ports for LDAP and LDAPS
    networking.firewall.allowedTCPPorts = [ 389 636 ];
  };
}