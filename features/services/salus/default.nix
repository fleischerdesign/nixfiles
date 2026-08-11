{
  config,
  lib,
  pkgs,
  inputs,
  features,
  ...
}:

let
  cfg = config.my.features.services.salus;
in
{
  options.my.features.services.salus = {
    enable = lib.mkEnableOption "Salus Health Data Tracker";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8200;
      description = "Port the Salus service listens on.";
    };

    databaseUrl = lib.mkOption {
      type = lib.types.str;
      default = "postgresql:///salus?host=/run/postgresql";
      description = "Database connection URL (PostgreSQL Unix socket default).";
    };

    sso = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Authentik OIDC Single Sign-On integration.";
      };

      issuerUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://auth.ancoris.ovh/application/o/salus/";
        description = "OIDC Issuer URL for Authentik.";
      };

      clientId = lib.mkOption {
        type = lib.types.str;
        default = "salus";
        description = "OIDC Client ID for Authentik.";
      };
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (features.requires [ "services.postgresql" ] config)

      {
        systemd.services.salus = {
          description = "Salus Health Data Tracker Service";
          wantedBy = [ "multi-user.target" ];
          after = [
            "network.target"
            "postgresql.service"
          ];

          environment = {
            PORT = toString cfg.port;
            SALUS_DATABASE_URL = cfg.databaseUrl;
          }
          // lib.optionalAttrs cfg.sso.enable {
            SALUS_OIDC_ISSUER_URL = cfg.sso.issuerUrl;
            SALUS_OIDC_CLIENT_ID = cfg.sso.clientId;
            SALUS_OAUTH_REDIRECT_BASE = config.my.endpoints.salus.publicUrl;
          };

          serviceConfig = {
            ExecStart = "${
              inputs.salus.packages.${pkgs.stdenv.hostPlatform.system}.default
            }/bin/salus --port ${toString cfg.port}";
            User = "salus";
            Group = "salus";

            StateDirectory = "salus";
            WorkingDirectory = "/var/lib/salus";

            Restart = "always";
            RestartSec = "5s";
          };
        };

        systemd.tmpfiles.rules = [
          "d /var/lib/salus 0750 salus salus -"
        ];

        users.users.salus = {
          isSystemUser = true;
          group = "salus";
          home = "/var/lib/salus";
        };
        users.groups.salus = { };

        services.postgresql = {
          ensureDatabases = [ "salus" ];
          ensureUsers = [
            {
              name = "salus";
              ensureDBOwnership = true;
            }
          ];
        };

        my.endpoints.salus = {
          host = config.networking.hostName;
          port = cfg.port;
          proxy = {
            enable = true;
            subdomain = "salus";
            websocket = true;
          };
        };
      }
    ]
  );
}
