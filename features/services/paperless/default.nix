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

    # 2. Template for the complex JSON Auth variable
    sops.templates."paperless.env" = {
      content = ''
        PAPERLESS_SOCIALACCOUNT_PROVIDERS={"openid_connect":{"APPS":[{"provider_id":"authentik","name":"Authentik","client_id":"INUkxbseZQSmCfa4SsFpW6mkzRME4Kc28Daw9PH2","secret":"${config.sops.placeholder.paperless_oidc_secret}","settings":{"server_url":"https://auth.ancoris.ovh/application/o/paperless/.well-known/openid-configuration"}}],"OAUTH_PKCE_ENABLED":"True"}}
      '';
    };

    services.paperless = {
      enable = true;
      port = 28981;
      address = "127.0.0.1";
      
      # Paths (Aligned with /data/storage mount)
      mediaDir = "/data/storage/media/docs/media";
      consumptionDir = "/data/storage/media/docs/consume";

      # Database Configuration
      settings = {
        PAPERLESS_REDIS = "redis://localhost:6379";
        PAPERLESS_DBHOST = "/run/postgresql";
        PAPERLESS_DBENGINE = "django.db.backends.postgresql";
        PAPERLESS_DBNAME = "paperless";
        PAPERLESS_DBUSER = "paperless";
        PAPERLESS_URL = "https://${cfg.expose.subdomain}.${config.my.features.services.caddy.baseDomain}";
        PAPERLESS_TIME_ZONE = "Europe/Berlin";
        PAPERLESS_OCR_LANGUAGE = "deu+eng";
        
        # Network / Proxy Configuration
        PAPERLESS_USE_X_FORWARDED_HOST = "true";
        PAPERLESS_PROXY_SSL_HEADER = "[\"HTTP_X_FORWARDED_PROTO\", \"https\"]";
        FORWARDED_ALLOW_IPS = "*";
        PAPERLESS_DEBUG = "true";
        
        # Fix SSL/Connectivity in Sandbox
        SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle.crt";
        REQUESTS_CA_BUNDLE = "/etc/ssl/certs/ca-bundle.crt";

        # Enable OIDC
        PAPERLESS_APPS = "allauth.socialaccount.providers.openid_connect";
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

    # Radically relax sandbox for debugging without overwriting ExecStart
    systemd.services = 
      let
        debugOptions = {
          RestrictAddressFamilies = lib.mkForce [ ];
          SystemCallFilter = lib.mkForce [ ];
          PrivateUsers = lib.mkForce false;
          RestrictNamespaces = lib.mkForce false;
          PrivateDevices = lib.mkForce false;
          PrivateMounts = lib.mkForce false;
          PrivateTmp = lib.mkForce false;
          ProtectSystem = lib.mkForce "none";
          ProtectHome = lib.mkForce false;
          ProtectHostname = lib.mkForce false;
          ProtectKernelLogs = lib.mkForce false;
          ProtectKernelModules = lib.mkForce false;
          ProtectKernelTunables = lib.mkForce false;
          ProtectControlGroups = lib.mkForce false;
          RestrictRealtime = lib.mkForce false;
          LockPersonality = lib.mkForce false;
          MemoryDenyWriteExecute = lib.mkForce false;
          EnvironmentFile = config.sops.templates."paperless.env".path;
        };
      in
      {
        paperless-web.serviceConfig = debugOptions;
        paperless-consumer.serviceConfig = debugOptions;
        paperless-task-queue.serviceConfig = debugOptions;
        paperless-scheduler.serviceConfig = debugOptions;
      };

    # Scanner Service (OCI Container)
    virtualisation.oci-containers.containers."node-hp-scan-to" = {
      image = "docker.io/manuc66/node-hp-scan-to:latest";
      environment = {
        IP = "192.168.178.62";
        LABEL = "paperless";
        TZ = "Europe/Berlin";
        PATTERN = "\"scan\"_dd-mm-yyyy_hh-MM-ss";
      };
      volumes = [
        "/data/storage/media/docs/consume:/scan"
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