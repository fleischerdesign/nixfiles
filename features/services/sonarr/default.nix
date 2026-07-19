{
  config,
  lib,
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
        sops.secrets.sonarr_api_key = {
          owner = "sonarr";
        };
        sops.templates."sonarr.env" = {
          owner = "sonarr";
          content = "SONARR__AUTH__APIKEY=${config.sops.placeholder.sonarr_api_key}";
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

        my.endpoints.sonarr = {
          host = config.networking.hostName;
          port = 8989;
        };
      }
    ]
  );
}
