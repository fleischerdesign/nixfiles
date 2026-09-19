{
  config,
  lib,
  features,
  ...
}:

let
  cfg = config.my.features.services.linkwarden;
in
{
  options.my.features.services.linkwarden = {
    enable = lib.mkEnableOption "Linkwarden";
    ssoAuthority = lib.mkOption {
      type = lib.types.str;
      default = "https://auth.${config.my.topology.domain}/application/o/linkwarden";
      description = "SSO Authority URL for Linkwarden.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (features.requires [ "services.postgresql" ] config)

      {
        services.linkwarden = {
          enable = true;
          host = "127.0.0.1";
          port = 3010;

          # Use central postgres
          database = {
            host = "/run/postgresql";
            name = "linkwarden";
            user = "linkwarden";
          };

          environment = {
            NEXT_PUBLIC_AUTHENTIK_ENABLED = "true";
            AUTHENTIK_ISSUER = cfg.ssoAuthority;
            # Linkwarden specific: NEXTAUTH_URL must end with /api/v1/auth
            NEXTAUTH_URL = "https://${config.my.contracts.provides.linkwarden.endpoints.web.canonicalDomain}/api/v1/auth";
            BASE_URL = "https://${config.my.contracts.provides.linkwarden.endpoints.web.canonicalDomain}";

            NEXT_PUBLIC_DISABLE_REGISTRATION = "true";
            NEXT_PUBLIC_CREDENTIALS_ENABLED = "false";
          };

          environmentFile = config.sops.secrets."services/apps/linkwarden_env".path;
        };

        # Inversion of Control: Declare PostgreSQL requirement
        my.contracts.consumes.linkwarden.postgresql.main = {
          database = "linkwarden";
          user = "linkwarden";
          ensureDBOwnership = true;
        };

        # Service Contract for Caddy, Firewall & OIDC
        my.contracts.provides.linkwarden = {
          endpoints.web = {
            port = 3010;
            protocol = "tcp";
            scope = "public";
            auth = "oidc";
            subdomain = "linkwarden";
            extraDomains = [
              "links.lan.${config.my.topology.domain}"
            ];
            oidc = {
              enable = true;
              clientId = "TBKFgLSIeXirGSZiuCFEXFeaUX3XaYt54FGr4VtM";
              clientSecretEnv = "AUTHENTIK_OIDC_LINKWARDEN_SECRET";
              secretPath = "services/apps/linkwarden_env";
              redirectPaths = [ "/api/v1/auth/callback/authentik" ];
              subMode = "hashed_user_id";
              includeClaimsInIdToken = true;
            };
            dashboard = {
              show = true;
              displayName = "Linkwarden";
              category = "Productivity";
              icon = "linkwarden";
            };
          };
          storage = {
            stateDirs = [ "/var/lib/linkwarden" ];
          };
        };

        # Secrets
        # Should contain:
        # AUTHENTIK_CLIENT_ID=...
        # AUTHENTIK_CLIENT_SECRET=...
        # NEXTAUTH_SECRET=... (random string)
        sops.secrets."services/apps/linkwarden_env" = {
          owner = "linkwarden";
        };
      }
    ]
  );
}
