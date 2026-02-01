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
    # Create a common media group for sharing files between services
    users.groups.media = { };

    # Add radarr user to the media group
    users.users.radarr = {
      extraGroups = [ "media" ];
    };

    # Ensure media directories on big storage exist with correct permissions
    systemd.tmpfiles.rules = [
      "d /data/storage/movies 0775 root media -"
      "d /data/storage/downloads 0775 root media -"
    ];

    services.radarr = {
      enable = true;
      settings = {
        auth = {
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
          ensureClauses.superuser = true;
        }
      ];
    };

    # Systemd hardening adjustment: 
    # 1. Allow writing to the movie and download directories
    # 2. Set UMask so created files are group-writable (media group)
    systemd.services.radarr.serviceConfig = {
      ReadWritePaths = [ 
        "/data/storage/movies" 
        "/data/storage/downloads"
      ];
      UMask = "0002";
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