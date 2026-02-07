{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.features.services.authentik.outpost.ldap;
  mackayeTailscaleIp = config.my.features.system.networking.topology.hosts.mackaye.tailscaleIp;
in
{
  options.my.features.services.authentik.outpost.ldap = {
    enable = lib.mkEnableOption "Authentik LDAP Outpost";
    
    coreAddress = lib.mkOption {
      type = lib.types.str;
      description = "The full URL (including protocol and port) of the Authentik Core server.";
    };

    tokenSecretName = lib.mkOption {
      type = lib.types.str;
      description = "The name of the secret in sops containing the Authentik token.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Secrets Setup
    sops.secrets."${cfg.tokenSecretName}" = {
      owner = "authentik-outpost-ldap";
      restartUnits = [ "authentik-outpost-ldap.service" ];
    };

    # Template for env vars
    sops.templates."authentik-outpost-ldap.env".content = ''
      AUTHENTIK_TOKEN=${config.sops.placeholder."${cfg.tokenSecretName}"}
    '';

    # Create system user
    users.users.authentik-outpost-ldap = {
      isSystemUser = true;
      group = "authentik-outpost-ldap";
    };
    users.groups.authentik-outpost-ldap = { };

    # Systemd Service
    systemd.services.authentik-outpost-ldap = {
      description = "Authentik LDAP Outpost";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        ExecStart = lib.getExe pkgs.authentik-outposts.ldap;
        EnvironmentFile = config.sops.templates."authentik-outpost-ldap.env".path;

        # Configure connection to Authentik Core
        Environment = [
          "AUTHENTIK_HOST=${cfg.coreAddress}"
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
    networking.firewall.allowedTCPPorts = [
      389
      636
    ];
  };
}
