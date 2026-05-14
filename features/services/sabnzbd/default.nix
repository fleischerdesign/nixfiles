{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.features.services.sabnzbd;
  domain = "${config.my.endpoints.sabnzbd.subdomain}.${config.my.features.services.caddy.baseDomain}";
in
{
  options.my.features.services.sabnzbd = {
    enable = lib.mkEnableOption "SABnzbd Usenet Downloader";
  };

  config = lib.mkIf cfg.enable {
    # 1. SOPS Secrets
    sops.secrets.newsgroup_ninja_password = {
      owner = "sabnzbd";
    };
    sops.secrets.sabnzbd_api_key = {
      owner = "sabnzbd";
    };
    sops.secrets.sabnzbd_nzb_key = {
      owner = "sabnzbd";
    };

    # 2. Template for sensitive values
    sops.templates."sabnzbd-secret.ini" = {
      owner = "sabnzbd";
      content = ''
        [misc]
        api_key = ${config.sops.placeholder.sabnzbd_api_key}
        nzb_key = ${config.sops.placeholder.sabnzbd_nzb_key}

        [servers]
        [[ninja]]
        password = ${config.sops.placeholder.newsgroup_ninja_password}
      '';
    };

    # 3. SABnzbd Service
    services.sabnzbd = {
      enable = true;
      user = "sabnzbd";
      group = "media";
      allowConfigWrite = false;
      configFile = null;
      secretFiles = [ config.sops.templates."sabnzbd-secret.ini".path ];

      settings = {
        misc = {
          port = 8080;
          host = "0.0.0.0";
          host_whitelist = "${if config.my.endpoints.sabnzbd.subdomain != null then "${config.my.endpoints.sabnzbd.subdomain}.${config.my.features.services.caddy.baseDomain}, " else ""}localhost, 127.0.0.1";
          inet_exposure = 4;
          download_dir = "/data/storage/downloads/incomplete";
          complete_dir = "/data/storage/downloads/complete";
          permissions = "775";
          cache_limit = "512M";
          bandwidth_max = "12.5M";
          bandwidth_perc = 90;
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
        categories = {
          movies = {
            name = "movies";
            order = 0;
          };
          tv = {
            name = "tv";
            order = 0;
          };
        };
      };
    };

    # Hoheit über den Download-Ordner
    users.groups.media = { };
    users.users.sabnzbd.extraGroups = [ "media" ];

    systemd.tmpfiles.rules = [
      "d /data/storage/downloads 0775 sabnzbd media -"
      "d /data/storage/downloads/incomplete 0775 sabnzbd media -"
      "d /data/storage/downloads/complete 0775 sabnzbd media -"
    ];

    systemd.services.sabnzbd.serviceConfig = {
      ReadWritePaths = [ "/data/storage/downloads" ];
      UMask = lib.mkForce "0002";
    };

    # Caddy Integration
    my.endpoints.sabnzbd = {
      host = config.networking.hostName;
      port = 8080;
    };
  };
}
