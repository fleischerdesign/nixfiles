{
  config,
  lib,
  features,
  ...
}:
let
  cfg = config.my.features.services.radarr;
in
{
  options.my.features.services.radarr = {
    enable = lib.mkEnableOption "Radarr Movie Manager";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (features.requires [ "services.postgresql" ] config)

      {
        # Ensure media group exists
        users.groups.media = { };

        # Explicitly define user and group to avoid SOPS evaluation issues
        users.users.radarr = {
          isSystemUser = true;
          group = "radarr";
          extraGroups = [ "media" ];
        };
        users.groups.radarr = { };

        # SOPS Secret for API Key
        sops.secrets."services/media/radarr_api_key" = {
          owner = "radarr";
        };
        sops.templates."radarr.env" = {
          owner = "radarr";
          content = "RADARR__AUTH__APIKEY=${config.sops.placeholder."services/media/radarr_api_key"}";
        };

        # Ownership management for storage
        systemd.tmpfiles.rules = [
          "d /data/storage/movies 2775 radarr media -"
        ];

        services.radarr = {
          enable = true;
          environmentFiles = [ config.sops.templates."radarr.env".path ];
          settings = {
            auth.method = "External";
            postgres = {
              host = "/run/postgresql";
              maindb = "radarr-main";
              logdb = "radarr-log";
              user = "radarr";
            };
          };
        };

        my.contracts.consumes.radarr.postgresql = {
          main = {
            database = "radarr-main";
            user = "radarr";
          };
          log = {
            database = "radarr-log";
            user = "radarr";
          };
        };

        systemd.services.radarr.serviceConfig = {
          ReadWritePaths = [
            "/data/storage/movies"
            "/data/storage/downloads"
          ];
          UMask = lib.mkForce "0002";
        };

        my.contracts.provides.radarr = {
          publications."web" = {
            scope = "internal";
            endpoint = "web";
            auth = "authentik";
            accessGroups = [ "media-users" ];
            subdomain = "radarr";

          };
          presentation.tiles."web" = {
            endpoint = "web";
            description = {
              de = "Filmbibliothek automatisch verwalten.";
              en = "Manage the movie library automatically.";
            };
            show = true;
            displayName = "Radarr";
            category = "Media";
            icon = "radarr";
          };
          telemetry.probes."web-http".endpoint = "web";
          telemetry.probes."web-http".kind = "http";
          telemetry.probes."web-http".path = "/ping";
          endpoints.web = {
            port = 7878;
            protocol = "tcp";
          };
          storage = {
            stateDirs = [ "/var/lib/radarr" ];
            regenerableDirs = [ "/data/storage/movies" ];
            cacheDirs = [ ];
          };
        };
      }
    ]
  );
}
