{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.features.services.authentik.outpost.ldap;
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
      default = "services/authentik/outposts/${config.networking.hostName}-ldap-token";
      description = "SOPS secret holding this host's dedicated LDAP outpost token.";
    };
    outpostName = lib.mkOption {
      type = lib.types.str;
      default = "vyrx-outpost-${config.networking.hostName}-ldap";
      description = "Name of the Authentik LDAP outpost managed for this host.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Secrets Setup
    sops.secrets."${cfg.tokenSecretName}" = {
      # Owned by the outpost service user by default. On the authentik server host
      # the server feature overrides this to "authentik" so the worker can read the
      # token through !File when applying the outpost blueprint.
      owner = lib.mkDefault "authentik-outpost-ldap";
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
          "AUTHENTIK_LOG_LEVEL=debug"
          # Bind the standard LDAP ports (the outpost binary defaults to 3389/6636).
          "AUTHENTIK_LISTEN__LDAP=0.0.0.0:389"
          "AUTHENTIK_LISTEN__LDAPS=0.0.0.0:636"
          # Keep the metrics listener off the server's and other outposts' ports.
          "AUTHENTIK_LISTEN__METRICS=127.0.0.1:9302"
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

    my.contracts.provides.authentik-ldap = {
      endpoints = {
        ldap = {
          port = 389;
          protocol = "tcp";
          scope = "internal";
          directAccess = {
            enable = true;
            protocol = "tcp";
            interface = "all";
          };
          monitoring.http.enable = false;
        };

        ldaps = {
          port = 636;
          protocol = "tcp";
          scope = "internal";
          directAccess = {
            enable = true;
            protocol = "tcp";
            interface = "all";
          };
          monitoring.http.enable = false;
        };
      };
    };
  };
}
