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
    # We use the local Authentik Outpost (Port 9000) for server-to-server traffic
    # to bypass internet connectivity issues with the vServer.
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
                  # Public URL for identity
                  server_url = "https://auth.ancoris.ovh/application/o/paperless";
                  # Public URL for Browser Redirect
                  authorization_url = "https://auth.ancoris.ovh/application/o/authorize/";
                  # Local URLs for Server-to-Server traffic (via Outpost)
                  token_url = "http://127.0.0.1:9000/application/o/token/";
                  userinfo_url = "http://127.0.0.1:9000/application/o/userinfo/";
                  jwks_url = "http://127.0.0.1:9000/application/o/paperless/jwks/";
                };
              }
            ];
            OAUTH_PKCE_ENABLED = "True";
          };
        }}
        PAPERLESS_USE_X_FORWARD_HOST=true
        PAPERLESS_USE_X_FORWARDED_PORT=true
        PAPERLESS_FORWARDED_ALLOW_IPS=*
        PAPERLESS_PROXY_SSL_HEADER=["HTTP_X_FORWARDED_PROTO", "https"]
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

    # Restore Hardening but keep the breakthrough network fixes
    systemd.services = 
      let
        # Secure networking defaults that worked
        netConfig = {
          PrivateNetwork = lib.mkForce false;
          # We need AF_NETLINK for DNS and AF_INET6/4 for connectivity
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
        # For other services, we just apply the network fixes
        paperless-consumer.serviceConfig = netConfig;
        paperless-task-queue.serviceConfig = netConfig;
        paperless-scheduler.serviceConfig = netConfig;
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
