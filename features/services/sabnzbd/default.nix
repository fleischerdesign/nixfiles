{ config, lib, pkgs, ... }:
let
  cfg = config.my.features.services.sabnzbd;
  domain = "${cfg.expose.subdomain}.${config.my.features.services.caddy.baseDomain}";
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
    # 1. SOPS Secret for the password
    sops.secrets.newsgroup_ninja_password = { owner = "sabnzbd"; };

    # 2. A template that creates a small INI snippet for the password
    sops.templates."sabnzbd-secret.ini" = {
      owner = "sabnzbd";
      content = ''
        [servers]
        [[ninja]]
        password = ${config.sops.placeholder.newsgroup_ninja_password}
      '';
    };

    # 3. SABnzbd using native settings
    services.sabnzbd = {
      enable = true;
      user = "sabnzbd";
      group = "media";
      
      # This option merges our secret password into the config at runtime
      secretFiles = [ config.sops.templates."sabnzbd-secret.ini".path ];

      settings = {
        misc = {
          port = 8080;
          host = "0.0.0.0";
          # FIX: Allow access via proxy and localhost (String, not list!)
          host_whitelist = "${domain}, localhost, 127.0.0.1";
          # FIX: 2 = Allow access from any IP (needed when behind Caddy)
          inet_exposure = 2; 
          
          download_dir = "/data/storage/downloads/incomplete";
          complete_dir = "/data/storage/downloads/complete";
          permissions = "775";
          cache_limit = "512M";
        };
        servers.ninja = {
          name = "Newsgroup Ninja";
          displayname = "Newsgroup Ninja";
          host = "news.newsgroup.ninja";
          port = 563;
          ssl = true;
          connections = 50;
          username = "Butchey";
          enable = true;
        };
      };
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