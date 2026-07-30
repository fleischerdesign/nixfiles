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
    if caddyOpt != null && caddyOpt.isDefined then config.my.features.services.caddy.baseDomain else null;
  authHost = if caddyBaseDomain != null then "auth.${caddyBaseDomain}" else "auth.ancoris.ovh";
in
{
  options.my.features.services.vaultwarden = {
    enable = lib.mkEnableOption "Vaultwarden";
    domain = lib.mkOption {
      type = lib.types.str;
      default = if caddyBaseDomain != null then "vault.${caddyBaseDomain}" else "vault.ancoris.ovh";
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
          environmentFile = config.sops.secrets.vaultwarden_env.path;
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

        # Caddy Reverse Proxy
        my.endpoints.vaultwarden = {
          host = config.networking.hostName;
          port = 8082;
          proxy = {
            enable = true;
            inherit (cfg) domain;
          };
        };

        # Secrets
        # Should contain SSO_CLIENT_ID and SSO_CLIENT_SECRET
        sops.secrets.vaultwarden_env = {
          owner = "vaultwarden";
        };
      }
    ]
  );
}
