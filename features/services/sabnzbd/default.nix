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
    # 1. SOPS Secret for the Newsgroup Server
    sops.secrets.newsgroup_ninja_password = { owner = "sabnzbd"; };

    # 2. Template for the SABnzbd configuration
    # This ensures the password is never in the Nix Store.
    sops.templates."sabnzbd.ini" = {
      owner = "sabnzbd";
      content = ''
        [misc]
        port = 8080
        host = 0.0.0.0
        permissions = 775
        # Aligned with your storage structure
        download_dir = /data/storage/downloads/incomplete
        complete_dir = /data/storage/downloads/complete
        
        [servers]
        [[ninja]]
        name = Newsgroup Ninja
        displayname = Newsgroup Ninja
        host = news.newsgroup.ninja
        port = 563
        ssl = 1
        connections = 50
        username = Butchey
        password = ${config.sops.placeholder.newsgroup_ninja_password}
        enable = 1
      '';
    };

    # 3. SABnzbd Service
    services.sabnzbd = {
      enable = true;
      user = "sabnzbd";
      group = "media";
      # Use the template-generated config file
      configFile = config.sops.templates."sabnzbd.ini".path;
    };

    # Ensure media group and directories exist
    users.groups.media = { };
    users.users.sabnzbd.extraGroups = [ "media" ];

    systemd.tmpfiles.rules = [
      "d /data/storage/downloads/incomplete 0775 root media -"
      "d /data/storage/downloads/complete 0775 root media -"
    ];

    # Systemd permissions for the storage drive
    systemd.services.sabnzbd.serviceConfig = {
      ReadWritePaths = [ "/data/storage/downloads" ];
      UMask = "0002";
    };

    # 4. Caddy Integration
    my.features.services.caddy.exposedServices = lib.mkIf cfg.expose.enable {
      "sabnzbd" = {
        port = 8080;
        auth = cfg.expose.auth;
        subdomain = cfg.expose.subdomain;
      };
    };
  };
}