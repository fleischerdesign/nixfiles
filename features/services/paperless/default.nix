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
    sops.secrets.paperless_oidc_secret = { };

    # Template only for the sensitive JSON block
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

    services.paperless = {
      enable = true;
      port = 28981;
      address = "127.0.0.1";
      
      mediaDir = "/data/storage/media/docs/media";
      consumptionDir = "/data/storage/media/docs/consume";

      settings = {
        PAPERLESS_REDIS = "redis://localhost:6379";
        PAPERLESS_DBHOST = "/run/postgresql";
        PAPERLESS_DBENGINE = "django.db.backends.postgresql";
        PAPERLESS_DBNAME = "paperless";
        PAPERLESS_DBUSER = "paperless";
        PAPERLESS_URL = "https://${cfg.expose.subdomain}.${config.my.features.services.caddy.baseDomain}";
        PAPERLESS_TIME_ZONE = "Europe/Berlin";
        PAPERLESS_OCR_LANGUAGE = "deu+eng";
        
        # Reverse Proxy & OIDC Stability
        PAPERLESS_USE_X_FORWARD_HOST = "true";
        PAPERLESS_USE_X_FORWARDED_PORT = "true";
        PAPERLESS_FORWARDED_ALLOW_IPS = "*";
        PAPERLESS_PROXY_SSL_HEADER = "[\"HTTP_X_FORWARDED_PROTO\", \"https\"]";
        PAPERLESS_SOCIALACCOUNT_REQUESTS_TIMEOUT = "30";
        
        PAPERLESS_APPS = "allauth.socialaccount.providers.openid_connect";
      };
    };

    services.postgresql = {
      ensureDatabases = [ "paperless" ];
      ensureUsers = [{ name = "paperless"; ensureDBOwnership = true; }];
    };

    # Essential Network Fixes (Minimal Overrides)
    systemd.services = 
      let
        netConfig = {
          PrivateNetwork = lib.mkForce false;
          RestrictAddressFamilies = lib.mkForce [ "AF_UNIX" "AF_INET" "AF_INET6" "AF_NETLINK" ];
          EnvironmentFile = config.sops.templates."paperless.env".path;
        };
      in
      {
        paperless-web = {
          serviceConfig = netConfig;
          unitConfig.JoinsNamespaceOf = lib.mkForce ""; 
          environment = {
            SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle.crt";
            REQUESTS_CA_BUNDLE = "/etc/ssl/certs/ca-bundle.crt";
          };
        };
        paperless-consumer.serviceConfig = netConfig;
        paperless-task-queue.serviceConfig = netConfig;
        paperless-scheduler.serviceConfig = netConfig;
      };

    # Scanner Service
    virtualisation.oci-containers.containers."node-hp-scan-to" = {
      image = "docker.io/manuc66/node-hp-scan-to:latest";
      environment = {
        IP = "192.168.178.62";
        LABEL = "paperless";
        TZ = "Europe/Berlin";
        PATTERN = "\"scan\"_dd-mm-yyyy_hh-MM-ss";
      };
      volumes = [ "/data/storage/media/docs/consume:/scan" ];
    };

    my.features.services.caddy.exposedServices = lib.mkIf cfg.expose.enable {
      "paperless" = {
        port = 28981;
        auth = false;
        subdomain = cfg.expose.subdomain;
      };
    };
  };
}
