{
  config,
  lib,
  features,
  ...
}:

let
  cfg = config.my.features.services.plausible;
in
{
  options.my.features.services.plausible = {
    enable = lib.mkEnableOption "Plausible Analytics";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (features.requires [ "services.postgresql" ] config)

      {
        # ClickHouse Database (Required for Plausible)
        services.clickhouse.enable = true;

        # Create user/group explicitly so sops can assign secrets
        users.users.plausible = {
          isSystemUser = true;
          group = "plausible";
        };
        users.groups.plausible = { };

        services.plausible = {
          enable = true;

          server = {
            baseUrl = "https://${config.my.contracts.provides.plausible.endpoints.web.canonicalDomain}";
            secretKeybaseFile = config.sops.secrets."services/apps/plausible_secret_key_base".path;
            port = 8000;
            listenAddress = "127.0.0.1";
            disableRegistration = true;
          };

          database = {
            clickhouse.url = "http://127.0.0.1:8123/plausible_events_db";
            postgres = {
              dbname = "plausible";
              socket = "/run/postgresql";
            };
          };
        };

        # Inject GeoIP path from the central geoipupdate service
        systemd.services.plausible.serviceConfig.Environment = [
          "IP_GEOLOCATION_DB=/var/lib/GeoIP/GeoLite2-City.mmdb"
        ];

        # Inversion of Control: Declare PostgreSQL requirement
        my.contracts.consumes.plausible.postgresql.main = {
          database = "plausible";
          user = "plausible";
          ensureDBOwnership = true;
        };

        # Service Contract for Caddy & Storage
        my.contracts.provides.plausible = {
          endpoints.web = {
            port = 8000;
            protocol = "tcp";
            scope = "public";
            auth = "none";
            subdomain = "plausible";
            dashboard = {
              description = {
                de = "Datenschutzfreundliche Web-Statistik.";
                en = "Privacy-friendly web analytics.";
              };
              show = true;
              displayName = "Plausible";
              category = "Observability & Tools";
              icon = "plausible";
            };
          };
          storage = {
            stateDirs = [ "/var/lib/plausible" ];
          };
        };

        # Secrets
        sops.secrets."services/apps/plausible_secret_key_base" = {
          owner = "plausible";
        };
      }
    ]
  );
}
