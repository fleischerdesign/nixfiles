{ config, lib, pkgs, ... }:

let
  cfg = config.my.features.services.vaultwarden;
in
{
  options.my.features.services.vaultwarden = {
    enable = lib.mkEnableOption "Vaultwarden";
  };

  config = lib.mkIf cfg.enable {
    services.vaultwarden = {
      enable = true;
      dbBackend = "postgresql";
      config = {
        DOMAIN = "https://vault.ancoris.ovh";
        SIGNUPS_ALLOWED = false;
        
        # OIDC / Authentik
        SSO_ENABLED = true;
        SSO_AUTHORITY = "https://auth.ancoris.ovh/application/o/vaultwarden/";
        SSO_SCOPES = "email profile offline_access";

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
    my.features.services.caddy.exposedServices = {
      "vaultwarden" = {
        port = 8082;
        fullDomain = "vault.ancoris.ovh";
      };
    };

    # Secrets
    # Should contain SSO_CLIENT_ID and SSO_CLIENT_SECRET
    sops.secrets.vaultwarden_env = { owner = "vaultwarden"; };
  };
}
