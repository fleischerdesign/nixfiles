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
    # Ensure media group exists
    users.groups.media = { };

    # Explicitly define user and group to avoid SOPS evaluation issues
    users.users.radarr = {
      isSystemUser = true;
      group = "radarr";
      extraGroups = [ "media" ];
    };
    users.groups.radarr = { };

    # SOPS Secret for API Key
    sops.secrets.radarr_api_key = { owner = "radarr"; };
    sops.templates."radarr.env" = {
      owner = "radarr";
      content = "RADARR__AUTH__APIKEY=${config.sops.placeholder.radarr_api_key}";
    };

    # Ownership management for storage
    systemd.tmpfiles.rules = [
      "d /data/storage/movies 2775 radarr media -"
    ];

    services.radarr = {
      enable = true;
      environmentFiles = [ config.sops.templates."radarr.env".path ];
      settings = {
        auth.method = "External";
        postgres = {
          host = "/run/postgresql";
          maindb = "radarr-main";
          logdb = "radarr-log";
          user = "radarr";
        };
      };
    };

    services.postgresql = {
      ensureDatabases = [ "radarr-main" "radarr-log" ];
      ensureUsers = [{
        name = "radarr";
        ensureDBOwnership = false;
        ensureClauses.superuser = true;
      }];
    };

    systemd.services.radarr.serviceConfig = {
      ReadWritePaths = [ "/data/storage/movies" "/data/storage/downloads" ];
      UMask = "0002";
    };

    my.features.services.caddy.exposedServices = lib.mkIf cfg.expose.enable {
      "radarr" = {
        port = 7878;
        auth = cfg.expose.auth;
        subdomain = cfg.expose.subdomain;
      };
    };
  };
}
