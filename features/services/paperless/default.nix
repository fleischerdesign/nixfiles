{
  config,
  lib,
  features,
  ...
}:
let
  cfg = config.my.features.services.paperless;
  topologyDomain = config.my.topology.domain;
  authHost = "auth.${topologyDomain}";
in
{
  options.my.features.services.paperless = {
    enable = lib.mkEnableOption "Paperless-ngx Document Management";
    ssoServerUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://${authHost}/application/o/paperless";
      description = "OIDC Issuer/Server URL for Authentik.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (features.requires [ "services.postgresql" "services.redis" ] config)

      {
        # Dependencies
        my.features.services.postgresql.enable = true;
        my.features.services.redis.enable = true;

        # 1. SOPS Secrets
        sops.secrets."services/apps/paperless_oidc_secret" = { };
        sops.secrets."services/apps/paperless_secret_key" = { };

        # 2. Template for the sensitive JSON Auth variable
        sops.templates."paperless.env" = {
          content = ''
            PAPERLESS_SECRET_KEY=${config.sops.placeholder."services/apps/paperless_secret_key"}
            PAPERLESS_SOCIALACCOUNT_PROVIDERS=${
              builtins.toJSON {
                openid_connect = {
                  APPS = [
                    {
                      provider_id = "authentik";
                      name = "Authentik";
                      client_id = "INUkxbseZQSmCfa4SsFpW6mkzRME4Kc28Daw9PH2";
                      secret = config.sops.placeholder."services/apps/paperless_oidc_secret";
                      settings = {
                        server_url = cfg.ssoServerUrl;
                        token_auth_method = "client_secret_basic";
                      };
                    }
                  ];
                  OAUTH_PKCE_ENABLED = "True";
                };
              }
            }
          '';
        };

        # Ensure media group exists
        users.groups.media = { };

        # Explicitly define user to avoid ownership issues
        users.users.paperless = {
          isSystemUser = true;
          group = "paperless";
          extraGroups = [ "media" ];
        };
        users.groups.paperless = { };

        # Create and enforce permissions recursively (Z)
        systemd.tmpfiles.rules = [
          "d /data/storage/docs 0775 paperless media -"
          "Z /data/storage/docs/media 0775 paperless media -"
          "Z /data/storage/docs/consume 0775 paperless media -"
        ];

        services.paperless = {
          enable = true;
          port = 28981;
          address = "127.0.0.1";

          mediaDir = "/data/storage/docs/media";
          consumptionDir = "/data/storage/docs/consume";

          settings = {
            PAPERLESS_REDIS = "redis://localhost:6379";
            PAPERLESS_DBHOST = "/run/postgresql";
            PAPERLESS_DBENGINE = "postgresql";
            PAPERLESS_DBNAME = "paperless";
            PAPERLESS_DBUSER = "paperless";
            PAPERLESS_URL =
              let
                ep = config.my.contracts.provides.paperless.endpoints.web;
              in
              lib.mkIf (ep.publicUrl != null) ep.publicUrl;
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

        # Inversion of Control: Declare PostgreSQL requirement
        my.contracts.consumes.paperless.postgresql.main = {
          database = "paperless";
          user = "paperless";
          ensureDBOwnership = true;
        };

        # Systemd overrides
        systemd.services.paperless-web = {
          serviceConfig.EnvironmentFile = config.sops.templates."paperless.env".path;
        };
        systemd.services.paperless-consumer.serviceConfig.EnvironmentFile =
          config.sops.templates."paperless.env".path;
        systemd.services.paperless-task-queue.serviceConfig.EnvironmentFile =
          config.sops.templates."paperless.env".path;
        systemd.services.paperless-scheduler.serviceConfig.EnvironmentFile =
          config.sops.templates."paperless.env".path;

        # Scanner Service
        virtualisation.oci-containers.backend = "podman";
        virtualisation.oci-containers.containers."node-hp-scan-to" = {
          image = "docker.io/manuc66/node-hp-scan-to:latest";
          environment = {
            PUID = "315";
            PGID = "987";
            # The address comes from the device inventory (my.topology.devices), which is the single
            # source for device addresses; the scanner is declared there as hom-prn-01.
            IP = config.my.topology.devices.hom-prn-01.ipv4;
            LABEL = "paperless";
            TZ = "Europe/Berlin";
            PATTERN = "\"scan\"_dd-mm-yyyy_hh-MM-ss";
          };
          volumes = [
            "/data/storage/docs/consume:/scan"
          ];
        };

        # Register with Caddy & Firewall via Service Contract
        my.contracts.provides.paperless = {
          endpoints.web = {
            port = 28981;
            protocol = "tcp";
            scope = "internal";
            auth = "oidc";
            accessGroups = [ "family" ];
            subdomain = "paperless";
            extraDomains = [
              "docs.lan.${topologyDomain}"
            ];
            oidc = {
              enable = true;
              clientId = "INUkxbseZQSmCfa4SsFpW6mkzRME4Kc28Daw9PH2";
              clientSecretEnv = "AUTHENTIK_OIDC_PAPERLESS_SECRET";
              secretPath = "services/apps/paperless_oidc_secret";
              redirectPaths = [ "/accounts/authentik/login/callback/" ];
              subMode = "hashed_user_id";
              includeClaimsInIdToken = true;
            };
            healthProbePath = "/";
            dashboard = {
              description = {
                de = "Belegarchiv mit Texterkennung.";
                en = "Document archive with OCR.";
              };
              show = true;
              displayName = "Paperless-ngx";
              category = "Productivity";
              icon = "paperless";
            };
          };
          storage = {
            stateDirs = [ "/var/lib/paperless" ];
            dataDirs = [
              "/data/storage/docs"
              "/var/lib/paperless/media"
            ];
            cacheDirs = [ ];
          };
        };
      }
    ]
  );
}
