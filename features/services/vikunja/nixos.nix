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
              pub = config.my.contracts.provides.vikunja.publications.web;
            in
            lib.mkIf (pub.canonicalDomain != null) pub.canonicalDomain;

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
                  pub = config.my.contracts.provides.vikunja.publications.web;
                in
                lib.mkIf (pub.publicUrl != null) "${pub.publicUrl}/";
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

        # Inversion of Control: Declare PostgreSQL requirement
        my.contracts.consumes.vikunja.postgresql.main = {
          database = "vikunja";
          user = "vikunja";
          ensureDBOwnership = true;
        };

        my.contracts.provides.vikunja = {
          publications."web" = {
            endpoint = "web";
            auth = "oidc";
            accessGroups = [ "family" ];
            subdomain = "vikunja";
            extraDomains = [
              "tasks.lan.${config.my.topology.domain}"
            ];

          };
          identity.oidc.web = {
            publication = "web";
            enable = true;
            clientId = cfg.ssoClientId;
            clientSecretEnv = "AUTHENTIK_OIDC_VIKUNJA_SECRET";
            secretPath = "services/apps/vikunja_oidc_secret";
            redirectPaths = [ "/auth/openid/authentik" ];
            subMode = "hashed_user_id";
            includeClaimsInIdToken = true;
          };
          presentation.tiles."web" = {
            endpoint = "web";
            description = {
              de = "Aufgaben, Listen und Projektboards.";
              en = "Tasks, lists and project boards.";
            };
            show = true;
            displayName = "Vikunja";
            category = "Productivity";
            icon = "vikunja";
          };
          endpoints.web = {
            port = 3456;
            protocol = "tcp";
          };
          storage = {
            stateDirs = [ "/var/lib/vikunja" ];
          };
        };
      }
    ]
  );
}
