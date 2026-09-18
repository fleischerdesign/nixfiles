{
  config,
  lib,
  features,
  ...
}:

let
  cfg = config.my.features.services.vikunja;
  authHost = "auth.${config.my.topology.domain}";
in
{
  options.my.features.services.vikunja = {
    enable = lib.mkEnableOption "Vikunja Task & Project Management";

    enableRegistration = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable open user registration in Vikunja";
    };

    ssoIssuerUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://${authHost}/application/o/vikunja/";
      description = "OIDC Issuer URL for Authentik";
    };

    ssoClientId = lib.mkOption {
      type = lib.types.str;
      default = "SqxgGKZ22SXY9KVEVZXeXyuf1M5EKguBrvpSGabH";
      description = "OIDC Client ID for Authentik";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (features.requires [ "services.postgresql" ] config)

      {
        sops.secrets."services/apps/vikunja_oidc_secret" = { };

        sops.templates."vikunja.env" = {
          content = ''
            VIKUNJA_AUTH_OPENID_PROVIDERS_AUTHENTIK_CLIENTSECRET=${
              config.sops.placeholder."services/apps/vikunja_oidc_secret"
            }
          '';
        };

        services.vikunja = {
          enable = true;
          port = 3456;
          address = "127.0.0.1";
          frontendScheme = "https";
          frontendHostname =
            let
              d = config.my.endpoints.vikunja.proxy.subdomain;
            in
            lib.mkIf (d != null) "${d}.${config.my.endpoints.vikunja.proxy.domain}";

          database = {
            type = "postgres";
            host = "/run/postgresql";
            user = "vikunja";
            database = "vikunja";
          };

          environmentFiles = [ config.sops.templates."vikunja.env".path ];

          settings = {
            service = {
              publicurl =
                let
                  d = config.my.endpoints.vikunja.proxy.subdomain;
                in
                lib.mkIf (d != null) "https://${d}.${config.my.endpoints.vikunja.proxy.domain}/";
              timezone = "Europe/Berlin";
              enableregistration = cfg.enableRegistration;
            };

            auth = {
              openid = {
                enabled = true;
                providers = {
                  authentik = {
                    name = "Authentik";
                    authurl = cfg.ssoIssuerUrl;
                    clientid = cfg.ssoClientId;
                  };
                };
              };
            };
          };
        };

        services.postgresql = {
          ensureDatabases = [ "vikunja" ];
          ensureUsers = [
            {
              name = "vikunja";
              ensureDBOwnership = true;
            }
          ];
        };

        my.endpoints.vikunja = {
          host = config.networking.hostName;
          port = 3456;
          displayName = "Vikunja";
          group = "Productivity";
          proxy = {
            enable = true;
            subdomain = "vikunja";
          };
          extraDomains = [
            "tasks.srv.lan.${config.my.topology.domain}"
          ];
          auth.oidc = {
            enable = true;
            clientId = cfg.ssoClientId;
            clientSecretEnv = "AUTHENTIK_OIDC_VIKUNJA_SECRET";
            secretPath = "services/apps/vikunja_oidc_secret";
            redirectPaths = [ "/auth/openid/authentik" ];
            subMode = "hashed_user_id";
            includeClaimsInIdToken = true;
          };
        };
      }
    ]
  );
}
