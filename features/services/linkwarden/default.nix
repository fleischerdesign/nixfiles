{ config, lib, pkgs, ... }:

let
  cfg = config.my.features.services.linkwarden;
in
{
  options.my.features.services.linkwarden = {
    enable = lib.mkEnableOption "Linkwarden";
  };

  config = lib.mkIf cfg.enable {
    services.linkwarden = {
      enable = true;
      host = "127.0.0.1";
      port = 3005;
      
      # Use central postgres
      database = {
        host = "/run/postgresql";
        name = "linkwarden";
        user = "linkwarden";
      };

      environment = {
        NEXT_PUBLIC_AUTHENTIK_ENABLED = "true";
        AUTHENTIK_ISSUER = "https://auth.ancoris.ovh/application/o/linkwarden";
        # Linkwarden specific: NEXTAUTH_URL must end with /api/v1/auth
        NEXTAUTH_URL = "https://linkwarden.mky.ancoris.ovh/api/v1/auth";
        BASE_URL = "https://linkwarden.mky.ancoris.ovh";
        
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
    my.features.services.caddy.exposedServices = {
      "linkwarden" = {
        port = 3005;
        fullDomain = "linkwarden.mky.ancoris.ovh";
      };
    };

    # Secrets
    # Should contain:
    # AUTHENTIK_CLIENT_ID=...
    # AUTHENTIK_CLIENT_SECRET=...
    # NEXTAUTH_SECRET=... (random string)
    sops.secrets.linkwarden_env = { owner = "linkwarden"; };
  };
}