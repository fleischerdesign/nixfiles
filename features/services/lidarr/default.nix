{ config, lib, pkgs, ... }:
let
  cfg = config.my.features.services.lidarr;
in
{
  options.my.features.services.lidarr = {
    enable = lib.mkEnableOption "Lidarr Music Manager";
    expose = {
      enable = lib.mkEnableOption "Expose via Caddy";
      subdomain = lib.mkOption { type = lib.types.str; default = "lidarr"; };
      auth = lib.mkEnableOption "Protect with Authentik";
    };
  };

  config = lib.mkIf cfg.enable {
    # Ensure media group exists
    users.groups.media = { };

    # Explicitly define user and group
    users.users.lidarr = {
      isSystemUser = true;
      group = "lidarr";
      extraGroups = [ "media" ];
    };
    users.groups.lidarr = { };

    # SOPS Secret for API Key
    sops.secrets.lidarr_api_key = { owner = "lidarr"; };
    sops.templates."lidarr.env" = {
      owner = "lidarr";
      content = "LIDARR__AUTH__APIKEY=${config.sops.placeholder.lidarr_api_key}";
    };

    # Ownership management for storage
    systemd.tmpfiles.rules = [
      "d /data/storage/music 2775 lidarr media -"
    ];

    services.lidarr = {
      enable = true;
      environmentFiles = [ config.sops.templates."lidarr.env".path ];
      settings = {
        auth.method = "External";
        postgres = {
          host = "/run/postgresql";
          maindb = "lidarr-main";
          logdb = "lidarr-log";
          user = "lidarr";
        };
      };
    };

    services.postgresql = {
      ensureDatabases = [ "lidarr-main" "lidarr-log" ];
      ensureUsers = [{
        name = "lidarr";
        ensureDBOwnership = false;
        ensureClauses.superuser = true;
      }];
    };

    systemd.services.lidarr.serviceConfig = {
      ReadWritePaths = [ "/data/storage/music" "/data/storage/downloads" ];
      UMask = lib.mkForce "0002";
    };

    my.features.services.caddy.exposedServices = lib.mkIf cfg.expose.enable {
      "lidarr" = {
        port = 8686;
        auth = cfg.expose.auth;
        subdomain = cfg.expose.subdomain;
      };
    };
  };
}