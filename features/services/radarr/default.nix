{ config, lib, pkgs, ... }:
let
  cfg = config.my.features.services.radarr;
in
{
  options.my.features.services.radarr = {
    enable = lib.mkEnableOption "Radarr Movie Manager";
    expose = {
      enable = lib.mkEnableOption "Expose via Caddy";
      subdomain = lib.mkOption { type = lib.types.str; default = "radarr"; };
      auth = lib.mkEnableOption "Protect with Authentik";
    };
  };

  config = lib.mkIf cfg.enable {
    services.radarr = {
      enable = true;
      settings = {
        auth = {
          # Correct internal property name for environment variable override
          method = "External";
        };
        # PostgreSQL Configuration
        postgres = {
          host = "/run/postgresql";
          maindb = "radarr-main";
          logdb = "radarr-log";
          user = "radarr";
        };
      };
    };

    # Ensure PostgreSQL database and user exist for Radarr
    services.postgresql = {
      ensureDatabases = [ "radarr-main" "radarr-log" ];
      ensureUsers = [
        {
          name = "radarr";
          ensureDBOwnership = false;
          # Superuser is often needed by *arr apps for initial schema migrations/extensions
          ensureClauses.superuser = true;
        }
      ];
    };

    # Register with Caddy Feature
    my.features.services.caddy.exposedServices = lib.mkIf cfg.expose.enable {
      "radarr" = {
        port = 7878;
        auth = cfg.expose.auth;
        subdomain = cfg.expose.subdomain;
      };
    };
  };
}
