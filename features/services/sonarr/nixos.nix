{
  config,
  lib,
  features,
  ...
}:
let
  cfg = config.my.features.services.sonarr;
in
{
  options.my.features.services.sonarr = {
    enable = lib.mkEnableOption "Sonarr TV Show Manager";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (features.requires [ "services.postgresql" ] config)

      {
        # Ensure media group exists
        users.groups.media = { };

        # Explicitly define user and group to avoid SOPS evaluation issues
        users.users.sonarr = {
          isSystemUser = true;
          group = "sonarr";
          extraGroups = [ "media" ];
        };
        users.groups.sonarr = { };

        # SOPS Secret for API Key
        sops.secrets."services/media/sonarr_api_key" = {
          owner = "sonarr";
        };
        sops.templates."sonarr.env" = {
          owner = "sonarr";
          content = "SONARR__AUTH__APIKEY=${config.sops.placeholder."services/media/sonarr_api_key"}";
        };

        # Ownership management for storage
        systemd.tmpfiles.rules = [
          "d /data/storage/tv 2775 sonarr media -"
        ];

        services.sonarr = {
          enable = true;
          environmentFiles = [ config.sops.templates."sonarr.env".path ];
          settings = {
            auth.method = "External";
            postgres = {
              host = "/run/postgresql";
              maindb = "sonarr-main";
              logdb = "sonarr-log";
              user = "sonarr";
            };
          };
        };

        services.postgresql = {
          ensureDatabases = [
            "sonarr-main"
            "sonarr-log"
          ];
          ensureUsers = [
            {
              name = "sonarr";
              ensureDBOwnership = false;
              ensureClauses.superuser = true;
            }
          ];
        };

        systemd.services.sonarr.serviceConfig = {
          ReadWritePaths = [
            "/data/storage/tv"
            "/data/storage/downloads"
          ];
          UMask = lib.mkForce "0002";
        };

        my.contracts.provides.sonarr = {
          publications."web" = {
            scope = "internal";
            endpoint = "web";
            auth = "authentik";
            accessGroups = [ "media-users" ];
            subdomain = "sonarr";

          };
          presentation.tiles."web" = {
            endpoint = "web";
            description = {
              de = "Serienbibliothek automatisch verwalten.";
              en = "Manage the show library automatically.";
            };
            show = true;
            displayName = "Sonarr";
            category = "Media";
            icon = "sonarr";
          };
          telemetry.probes."web-http".endpoint = "web";
          telemetry.probes."web-http".kind = "http";
          telemetry.probes."web-http".path = "/ping";
          endpoints.web = {
            port = 8989;
            protocol = "tcp";
          };
          storage = {
            stateDirs = [ "/var/lib/sonarr" ];
            regenerableDirs = [ "/data/storage/tv" ];
            cacheDirs = [ ];
          };
        };
      }
    ]
  );
}
