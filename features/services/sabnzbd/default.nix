{ config, lib, pkgs, ... }:
let
  cfg = config.my.features.services.sabnzbd;
in
{
  options.my.features.services.sabnzbd = {
    enable = lib.mkEnableOption "SABnzbd Downloader";
    expose = {
      enable = lib.mkEnableOption "Expose via Caddy";
      subdomain = lib.mkOption { type = lib.types.str; default = "sabnzbd"; };
      auth = lib.mkEnableOption "Protect with Authentik";
    };
  };

  config = lib.mkIf cfg.enable {
    # Ensure media group exists
    users.groups.media = { };

    # Add sabnzbd user to the media group
    users.users.sabnzbd = {
      extraGroups = [ "media" ];
    };

    services.sabnzbd = {
      enable = true;
      # Default port is 8080
    };

    # Systemd hardening adjustment: 
    # 1. Allow writing to the download directory
    # 2. Set UMask so created files are group-writable (media group)
    systemd.services.sabnzbd.serviceConfig = {
      ReadWritePaths = [ "/data/storage/downloads" ];
      UMask = "0002";
    };

    # Register with Caddy Feature
    my.features.services.caddy.exposedServices = lib.mkIf cfg.expose.enable {
      "sabnzbd" = {
        port = 8080;
        auth = cfg.expose.auth;
        subdomain = cfg.expose.subdomain;
      };
    };
  };
}
