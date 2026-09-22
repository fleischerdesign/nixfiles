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
          endpoints.web = {
            port = 8989;
            protocol = "tcp";
            scope = "internal";
            auth = "authentik";
            accessGroups = [ "media-users" ];
            subdomain = "sonarr";
            healthProbePath = "/ping";
            dashboard = {
              description = {
                de = "Serienbibliothek automatisch verwalten.";
                en = "Manage the show library automatically.";
              };
              show = true;
              displayName = "Sonarr";
              category = "Media";
              icon = "sonarr";
            };
          };
          storage = {
            stateDirs = [ "/var/lib/sonarr" ];
            dataDirs = [ "/data/storage/tv" ];
            cacheDirs = [ ];
          };
        };
      }
    ]
  );
}
