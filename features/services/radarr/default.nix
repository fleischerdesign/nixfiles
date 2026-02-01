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
    # Hoheit über den Movie-Ordner
    users.groups.media = { };
    users.users.radarr.extraGroups = [ "media" ];

    systemd.tmpfiles.rules = [
      "d /data/storage/movies 0775 radarr media -"
    ];

    services.radarr = {
      enable = true;
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
      # Darf in Movies (Besitzer) und Downloads (Gruppe) schreiben
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
