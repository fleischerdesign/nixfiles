{ config, lib, pkgs, ... }:
let
  cfg = config.my.features.services.sonarr;
in
{
  options.my.features.services.sonarr = {
    enable = lib.mkEnableOption "Sonarr Series Manager";
    expose = {
      enable = lib.mkEnableOption "Expose via Caddy";
      subdomain = lib.mkOption { type = lib.types.str; default = "sonarr"; };
      auth = lib.mkEnableOption "Protect with Authentik";
    };
  };

  config = lib.mkIf cfg.enable {
    # Hoheit über den Serien-Ordner
    users.groups.media = { };
    users.users.sonarr.extraGroups = [ "media" ];

    systemd.tmpfiles.rules = [
      "d /data/storage/tv 0775 sonarr media -"
    ];

    services.sonarr = {
      enable = true;
      settings = {
        auth.method = "External";
        postgres = {
          host = "/run/postgresql";
          maindb = "sonarr-main";
          logdb = "sonarr-log";
          user = "sonarr";
        };
      };
    };

    services.postgresql = {
      ensureDatabases = [ "sonarr-main" "sonarr-log" ];
      ensureUsers = [{
        name = "sonarr";
        ensureDBOwnership = false;
        ensureClauses.superuser = true;
      }];
    };

    systemd.services.sonarr.serviceConfig = {
      # Darf in TV (Besitzer) und Downloads (Gruppe) schreiben
      ReadWritePaths = [ "/data/storage/tv" "/data/storage/downloads" ];
      UMask = "0002";
    };

    my.features.services.caddy.exposedServices = lib.mkIf cfg.expose.enable {
      "sonarr" = {
        port = 8989;
        auth = cfg.expose.auth;
        subdomain = cfg.expose.subdomain;
      };
    };
  };
}