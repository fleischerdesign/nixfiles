{
  config,
  lib,
  features,
  ...
}:
let
  cfg = config.my.features.services.prowlarr;
in
{
  options.my.features.services.prowlarr = {
    enable = lib.mkEnableOption "Prowlarr Indexer Manager";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (features.requires [ "services.postgresql" ] config)

      {
        # Ensure media group exists
        users.groups.media = { };

        # Explicitly define user and group to avoid SOPS evaluation issues
        users.users.prowlarr = {
          isSystemUser = true;
          group = "prowlarr";
          extraGroups = [ "media" ];
        };
        users.groups.prowlarr = { };

        # SOPS Secret for API Key
        sops.secrets."services/media/prowlarr_api_key" = {
          owner = "prowlarr";
        };
        sops.templates."prowlarr.env" = {
          owner = "prowlarr";
          content = "PROWLARR__AUTH__APIKEY=${config.sops.placeholder."services/media/prowlarr_api_key"}";
        };

        services.prowlarr = {
          enable = true;
          environmentFiles = [ config.sops.templates."prowlarr.env".path ];
          settings = {
            auth = {
              method = "External";
            };
            # PostgreSQL Configuration
            postgres = {
              host = "/run/postgresql";
              maindb = "prowlarr-main";
              logdb = "prowlarr-log";
              user = "prowlarr";
            };
          };
        };

        # Ensure PostgreSQL database and user exist for Prowlarr
        services.postgresql = {
          ensureDatabases = [
            "prowlarr-main"
            "prowlarr-log"
          ];
          ensureUsers = [
            {
              name = "prowlarr";
              ensureDBOwnership = false;
              ensureClauses.superuser = true;
            }
          ];
        };

        my.contracts.provides.prowlarr = {
          endpoints.web = {
            port = 9696;
            protocol = "tcp";
            scope = "internal";
            auth = "authentik";
            accessGroups = [ "media-users" ];
            subdomain = "prowlarr";
            healthProbePath = "/ping";
            dashboard = {
              description = {
                de = "Indexer-Verwaltung für den Medien-Stack.";
                en = "Indexer management for the media stack.";
              };
              show = true;
              displayName = "Prowlarr";
              category = "Media";
              icon = "prowlarr";
            };
          };
          storage = {
            stateDirs = [ "/var/lib/prowlarr" ];
            dataDirs = [ ];
            cacheDirs = [ ];
          };
        };
      }
    ]
  );
}
