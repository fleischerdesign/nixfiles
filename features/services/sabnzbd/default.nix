{
  config,
  lib,
  ...
}:
let
  cfg = config.my.features.services.sabnzbd;
in
{
  options.my.features.services.sabnzbd = {
    enable = lib.mkEnableOption "SABnzbd Usenet Downloader";
    downloadDir = lib.mkOption {
      type = lib.types.str;
      default = "/data/storage/downloads";
      description = "Base download directory for SABnzbd.";
    };
    server = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Configure default Usenet server connection.";
      };
      name = lib.mkOption {
        type = lib.types.str;
        default = "Newsgroup Ninja";
        description = "Friendly display name of the Usenet server.";
      };
      host = lib.mkOption {
        type = lib.types.str;
        default = "news.newsgroup.ninja";
        description = "Usenet server hostname.";
      };
      port = lib.mkOption {
        type = lib.types.int;
        default = 563;
        description = "Usenet server connection port.";
      };
      ssl = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable SSL/TLS for Usenet server connection.";
      };
      connections = lib.mkOption {
        type = lib.types.int;
        default = 50;
        description = "Number of concurrent connections to the Usenet server.";
      };
      username = lib.mkOption {
        type = lib.types.str;
        default = "Butchey";
        description = "Usenet server account username.";
      };
    };
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
          host_whitelist = "${
            if config.my.endpoints.sabnzbd.proxy.subdomain != null then
              "${config.my.endpoints.sabnzbd.proxy.subdomain}.${config.my.endpoints.sabnzbd.proxy.domain}, "
            else
              ""
          }localhost, 127.0.0.1";
          inet_exposure = 4;
          download_dir = "${cfg.downloadDir}/incomplete";
          complete_dir = "${cfg.downloadDir}/complete";
          permissions = "775";
          cache_limit = "512M";
          bandwidth_max = "12.5M";
          bandwidth_perc = 90;
        };
        servers = lib.mkIf cfg.server.enable {
          ninja = {
            inherit (cfg.server)
              name
              host
              port
              ssl
              connections
              username
              ;
            displayname = cfg.server.name;
            enable = true;
          };
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
      "d ${cfg.downloadDir} 0775 sabnzbd media -"
      "d ${cfg.downloadDir}/incomplete 0775 sabnzbd media -"
      "d ${cfg.downloadDir}/complete 0775 sabnzbd media -"
    ];

    systemd.services.sabnzbd.serviceConfig = {
      ReadWritePaths = [ cfg.downloadDir ];
      UMask = lib.mkForce "0002";
    };

    # Caddy Integration
    my.endpoints.sabnzbd = {
      host = config.networking.hostName;
      port = 8080;
    };
  };
}
