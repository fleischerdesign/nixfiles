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
        my.contracts.consumes.prowlarr.postgresql = {
          main = {
            database = "prowlarr-main";
            user = "prowlarr";
          };
          log = {
            database = "prowlarr-log";
            user = "prowlarr";
          };
        };

        my.contracts.provides.prowlarr = {
          publications."web" = {
            scope = "internal";
            endpoint = "web";
            auth = "authentik";
            accessGroups = [ "media-users" ];
            subdomain = "prowlarr";

          };
          presentation.tiles."web" = {
            endpoint = "web";
            description = {
              de = "Indexer-Verwaltung für den Medien-Stack.";
              en = "Indexer management for the media stack.";
            };
            show = true;
            displayName = "Prowlarr";
            category = "Media";
            icon = "prowlarr";
          };
          telemetry.probes."web-http".endpoint = "web";
          telemetry.probes."web-http".kind = "http";
          telemetry.probes."web-http".path = "/ping";
          endpoints.web = {
            port = 9696;
            protocol = "tcp";
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
