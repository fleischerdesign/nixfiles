{
  config,
  options,
  lib,
  features,
  ...
}:

let
  cfg = config.my.features.services.vaultwarden;
  caddyOpt = options.my.features.services.caddy.baseDomain or null;
  caddyBaseDomain =
    if caddyOpt != null && caddyOpt.isDefined then
      config.my.features.services.caddy.baseDomain
    else
      null;
  topologyDomain = config.my.topology.domain;
  authHost = "auth.${topologyDomain}";
in
{
  options.my.features.services.vaultwarden = {
    enable = lib.mkEnableOption "Vaultwarden";
    domain = lib.mkOption {
      type = lib.types.str;
      default =
        if caddyBaseDomain != null then "vault.${caddyBaseDomain}" else "vault.edge.${topologyDomain}";
      description = "Full domain name for Vaultwarden.";
    };
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
            DOMAIN = "https://${cfg.domain}";
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
            inherit (cfg) domain;
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
