{
  config,
  lib,
  features,
  ...
}:

let
  cfg = config.my.features.services.vaultwarden;
  topologyDomain = config.my.topology.domain;
  authHost = "auth.${topologyDomain}";
in
{
  options.my.features.services.vaultwarden = {
    enable = lib.mkEnableOption "Vaultwarden";
    ssoAuthority = lib.mkOption {
      type = lib.types.str;
      default = "https://${authHost}/application/o/vaultwarden/";
      description = "OIDC Issuer/Authority URL for single sign-on.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (features.requires [ "services.postgresql" ] config)

      {
        services.vaultwarden = {
          enable = true;
          dbBackend = "postgresql";
          config = {
            DOMAIN = "https://${config.my.contracts.provides.vaultwarden.endpoints.web.canonicalDomain}";
            SIGNUPS_ALLOWED = false;

            # OIDC / Authentik
            SSO_ENABLED = true;
            SSO_ONLY = true;
            SSO_AUTHORITY = cfg.ssoAuthority;
            SSO_SCOPES = "email profile offline_access";
            SSO_ALLOW_UNKNOWN_EMAIL_VERIFICATION = true;

            DATABASE_URL = "postgresql://%2Frun%2Fpostgresql/vaultwarden";

            ROCKET_ADDRESS = "127.0.0.1";
            ROCKET_PORT = 8082;
          };
          environmentFile = config.sops.secrets."services/apps/vaultwarden_env".path;
        };

        # Ensure Postgres DB exists
        services.postgresql = {
          ensureDatabases = [ "vaultwarden" ];
          ensureUsers = [
            {
              name = "vaultwarden";
              ensureDBOwnership = true;
            }
          ];
        };

        # Service Contract for Caddy, Firewall & OIDC
        my.contracts.provides.vaultwarden = {
          endpoints.web = {
            port = 8082;
            protocol = "tcp";
            scope = "public";
            auth = "oidc";
            accessGroups = [ "family" ];
            subdomain = "vault";
            extraDomains = [
              "vault.${topologyDomain}"
            ];
            oidc = {
              enable = true;
              clientId = "IW0W9V9cLTDaMbdtXy7lGwHi55Vakio8E2tTSvsg";
              clientSecretEnv = "AUTHENTIK_OIDC_VAULTWARDEN_SECRET";
              secretPath = "services/apps/vaultwarden_env";
              redirectPaths = [ "/identity/connect/oidc-signin" ];
              subMode = "user_username";
              includeClaimsInIdToken = true;
            };
            dashboard = {
              description = {
                de = "Passwort-Tresor im eigenen Netz.";
                en = "Password vault in your own network.";
              };
              show = true;
              displayName = "Vaultwarden";
              category = "Security";
              icon = "vaultwarden";
            };
          };
          storage = {
            stateDirs = [ "/var/lib/vaultwarden" ];
          };
        };

        # Secrets
        # Should contain SSO_CLIENT_ID and SSO_CLIENT_SECRET
        sops.secrets."services/apps/vaultwarden_env" = {
          owner = "vaultwarden";
        };
      }
    ]
  );
}
