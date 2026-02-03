{ config, lib, pkgs, ... }:

let
  cfg = config.my.features.services.authentik;
in
{
  options.my.features.services.authentik = {
    enable = lib.mkEnableOption "Authentik Identity Provider (Server)";
  };

  config = lib.mkIf cfg.enable {
    services.authentik = {
      enable = true;
      
      settings = {
        email = {
          # SMTP settings should be configured via sops secrets or environment variables
        };
        disable_startup_analytics = true;
        avatars = "gravatar";
        
        # Configure Redis to use the central 'system' instance
        redis = {
          host = "127.0.0.1";
          port = 6379;
        };

        # Postgres is handled by the module via environment variables or settings
        postgresql = {
          host = "localhost";
          name = "authentik";
          user = "authentik";
        };
      };

      environmentFile = config.sops.secrets.authentik_core_env.path;
    };

    # Ensure database exists in central PostgreSQL
    services.postgresql = {
      ensureDatabases = [ "authentik" ];
      ensureUsers = [
        {
          name = "authentik";
          ensureDBOwnership = true;
        }
      ];
    };

    # Reverse Proxy using the fixed domain
    my.features.services.caddy.exposedServices = {
      "authentik" = {
        port = 9000;
        fullDomain = "auth.ancoris.ovh";
      };
    };

    # Secrets
    sops.secrets.authentik_core_env = {
      owner = "authentik";
    };
  };
}