{ config, lib, pkgs, ... }:
let
  cfg = config.my.features.services.paperless;
in
{
  options.my.features.services.paperless = {
    enable = lib.mkEnableOption "Paperless-ngx Document Management";
    expose = {
      enable = lib.mkEnableOption "Expose via Caddy";
      subdomain = lib.mkOption { type = lib.types.str; default = "paperless"; };
    };
  };

  config = lib.mkIf cfg.enable {
    # 1. SOPS Secret for OIDC
    sops.secrets.paperless_oidc_secret = { };

    # 2. Template for the sensitive JSON Auth variable
    sops.templates."paperless.env" = {
      content = ''
        PAPERLESS_SOCIALACCOUNT_PROVIDERS=${builtins.toJSON {
          openid_connect = {
            APPS = [
              {
                provider_id = "authentik";
                name = "Authentik";
                client_id = "INUkxbseZQSmCfa4SsFpW6mkzRME4Kc28Daw9PH2";
                secret = config.sops.placeholder.paperless_oidc_secret;
                settings = {
                  server_url = "https://auth.ancoris.ovh/application/o/paperless";
                };
              }
            ];
            OAUTH_PKCE_ENABLED = "True";
          };
        }}
      '';
    };

    # Ensure media group exists and paperless user is part of it
    users.groups.media = { };
    users.users.paperless.extraGroups = [ "media" ];

    # Create the correct directories on the storage drive
    systemd.tmpfiles.rules = [
      "d /data/storage/docs 0775 paperless media -"
      "d /data/storage/docs/media 0775 paperless media -"
      "d /data/storage/docs/consume 0775 paperless media -"
    ];

    services.paperless = {
      enable = true;
      port = 28981;
      address = "127.0.0.1";
      
      # Corrected Paths
      mediaDir = "/data/storage/docs/media";
      consumptionDir = "/data/storage/docs/consume";

      settings = {
        PAPERLESS_REDIS = "redis://localhost:6379";
        PAPERLESS_DBHOST = "/run/postgresql";
        PAPERLESS_DBENGINE = "django.db.backends.postgresql";
        PAPERLESS_DBNAME = "paperless";
        PAPERLESS_DBUSER = "paperless";
        PAPERLESS_URL = "https://${cfg.expose.subdomain}.${config.my.features.services.caddy.baseDomain}";
        PAPERLESS_TIME_ZONE = "Europe/Berlin";
        PAPERLESS_OCR_LANGUAGE = "deu+eng";
        
        # Stability and Proxy Fixes
        PAPERLESS_SOCIALACCOUNT_REQUESTS_TIMEOUT = "30";
        PAPERLESS_USE_X_FORWARD_HOST = "true";
        PAPERLESS_USE_X_FORWARDED_PORT = "true";
        PAPERLESS_FORWARDED_ALLOW_IPS = "*";
        PAPERLESS_PROXY_SSL_HEADER = "[\"HTTP_X_FORWARDED_PROTO\", \"https\"]";

        # Enable OIDC
        PAPERLESS_APPS = "allauth.socialaccount.providers.openid_connect";
        PAPERLESS_DEBUG = "false";
      };
    };

    # Ensure PostgreSQL database and user exist for Paperless
    services.postgresql = {
      ensureDatabases = [ "paperless" ];
      ensureUsers = [
        {
          name = "paperless";
          ensureDBOwnership = true;
        }
      ];
    };

    # Systemd overrides
    systemd.services.paperless-web = {
      serviceConfig.EnvironmentFile = config.sops.templates."paperless.env".path;
      environment = {
        SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle.crt";
        REQUESTS_CA_BUNDLE = "/etc/ssl/certs/ca-bundle.crt";
      };
    };
    systemd.services.paperless-consumer.serviceConfig.EnvironmentFile = config.sops.templates."paperless.env".path;
    systemd.services.paperless-task-queue.serviceConfig.EnvironmentFile = config.sops.templates."paperless.env".path;
    systemd.services.paperless-scheduler.serviceConfig.EnvironmentFile = config.sops.templates."paperless.env".path;

    # Scanner Service
    virtualisation.oci-containers.containers."node-hp-scan-to" = {
      image = "docker.io/manuc66/node-hp-scan-to:latest";
      environment = {
        IP = "192.168.178.62";
        LABEL = "paperless";
        TZ = "Europe/Berlin";
        PATTERN = "\"scan\"_dd-mm-yyyy_hh-MM-ss";
      };
      volumes = [
        "/data/storage/docs/consume:/scan"
      ];
    };

    # Register with Caddy Feature
    my.features.services.caddy.exposedServices = lib.mkIf cfg.expose.enable {
      "paperless" = {
        port = 28981;
        auth = false; # Native OIDC
        subdomain = cfg.expose.subdomain;
      };
    };
  };
}
