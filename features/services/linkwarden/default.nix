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
    domain = lib.mkOption {
      type = lib.types.str;
      default = "linkwarden.mky.ancoris.ovh";
      description = "Domain name for Linkwarden.";
    };
    ssoAuthority = lib.mkOption {
      type = lib.types.str;
      default = "https://auth.ancoris.ovh/application/o/linkwarden";
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
            NEXTAUTH_URL = "https://${cfg.domain}/api/v1/auth";
            BASE_URL = "https://${cfg.domain}";

            NEXT_PUBLIC_DISABLE_REGISTRATION = "true";
            NEXT_PUBLIC_CREDENTIALS_ENABLED = "false";
          };

          environmentFile = config.sops.secrets.linkwarden_env.path;
        };

        # Ensure Postgres DB exists
        services.postgresql = {
          ensureDatabases = [ "linkwarden" ];
          ensureUsers = [
            {
              name = "linkwarden";
              ensureDBOwnership = true;
            }
          ];
        };

        # Caddy Reverse Proxy
        my.endpoints.linkwarden = {
          host = config.networking.hostName;
          port = 3010;
          proxy = {
            enable = true;
            inherit (cfg) domain;
          };
        };

        # Secrets
        # Should contain:
        # AUTHENTIK_CLIENT_ID=...
        # AUTHENTIK_CLIENT_SECRET=...
        # NEXTAUTH_SECRET=... (random string)
        sops.secrets.linkwarden_env = {
          owner = "linkwarden";
        };
      }
    ]
  );
}
