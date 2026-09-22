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

        services.postgresql = {
          ensureDatabases = [
            "radarr-main"
            "radarr-log"
          ];
          ensureUsers = [
            {
              name = "radarr";
              ensureDBOwnership = false;
              ensureClauses.superuser = true;
            }
          ];
        };

        systemd.services.radarr.serviceConfig = {
          ReadWritePaths = [
            "/data/storage/movies"
            "/data/storage/downloads"
          ];
          UMask = lib.mkForce "0002";
        };

        my.contracts.provides.radarr = {
          endpoints.web = {
            port = 7878;
            protocol = "tcp";
            scope = "internal";
            auth = "authentik";
            accessGroups = [ "media-users" ];
            subdomain = "radarr";
            healthProbePath = "/ping";
            dashboard = {
              description = {
                de = "Filmbibliothek automatisch verwalten.";
                en = "Manage the movie library automatically.";
              };
              show = true;
              displayName = "Radarr";
              category = "Media";
              icon = "radarr";
            };
          };
          storage = {
            stateDirs = [ "/var/lib/radarr" ];
            dataDirs = [ "/data/storage/movies" ];
            cacheDirs = [ ];
          };
        };
      }
    ]
  );
}
