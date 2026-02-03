{ config, lib, pkgs, ... }:

let
  cfg = config.my.features.services.plausible;
in
{
  options.my.features.services.plausible = {
    enable = lib.mkEnableOption "Plausible Analytics";
  };

  config = lib.mkIf cfg.enable {
    # ClickHouse Database (Required for Plausible)
    services.clickhouse.enable = true;

    # Create user/group explicitly so sops can assign secrets
    users.users.plausible = {
      isSystemUser = true;
      group = "plausible";
    };
    users.groups.plausible = {};

    services.plausible = {
      enable = true;
      
      server = {
        baseUrl = "https://plausible.mky.ancoris.ovh";
        secretKeybaseFile = config.sops.secrets.plausible_secret_key_base.path;
        port = 8000;
        listenAddress = "127.0.0.1";
        disableRegistration = false; 
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

    # Ensure Postgres DB exists in the central instance
    services.postgresql = {
      ensureDatabases = [ "plausible" ];
      ensureUsers = [
        {
          name = "plausible";
          ensureDBOwnership = true;
        }
      ];
    };

    # Caddy Reverse Proxy
    my.features.services.caddy.exposedServices = {
      "plausible" = {
        port = 8000;
        subdomain = "plausible";
      };
    };

    # Secrets
    sops.secrets.plausible_secret_key_base = { owner = "plausible"; };
  };
}