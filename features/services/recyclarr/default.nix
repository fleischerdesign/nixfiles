{ config, lib, pkgs, ... }:
let
  cfg = config.my.features.services.recyclarr;
in
{
  options.my.features.services.recyclarr = {
    enable = lib.mkEnableOption "Recyclarr Configuration Sync";
  };

  config = lib.mkIf cfg.enable {
    # 1. SOPS secrets
    sops.secrets.radarr_api_key = { };
    sops.secrets.sonarr_api_key = { };

    # 2. Create environment file for Recyclarr
    sops.templates."recyclarr.env" = {
      owner = "recyclarr";
      content = ''
        RADARR_API_KEY=${config.sops.placeholder.radarr_api_key}
        SONARR_API_KEY=${config.sops.placeholder.sonarr_api_key}
      '';
    };

    # 3. Recyclarr Service Configuration - Renaming instances to avoid "Duplicate Instances" error
    services.recyclarr = {
      enable = true;
      schedule = "daily";
      
      configuration = {
        # Radarr Instance
        radarr.radarr-instance = {
          base_url = "http://localhost:7878";
          api_key = "!env_var RADARR_API_KEY";
          
          quality_definition.type = "movie";

          custom_formats = [
            {
              trash_ids = [ "86bc3115eb4e9873ac96904a4a68e19e" ]; # German (Language Profile)
              assign_scores_to = [
                { name = "HD - 1080p"; score = 100; }
              ];
            }
          ];
        };

        # Sonarr Instance
        sonarr.sonarr-instance = {
          base_url = "http://localhost:8989";
          api_key = "!env_var SONARR_API_KEY";

          quality_definition.type = "series";

          custom_formats = [
            {
              trash_ids = [ "8a9fcdbb445f2add0505926df3bb7b8a" ]; # German (Language Profile)
              assign_scores_to = [
                { name = "HD - 1080p"; score = 100; }
              ];
            }
          ];
        };
      };
    };

    # Inject environment variables into the systemd service
    systemd.services.recyclarr.serviceConfig.EnvironmentFile = config.sops.templates."recyclarr.env".path;

    # Explicitly define user and group
    users.users.recyclarr = {
      isSystemUser = true;
      group = "recyclarr";
    };
    users.groups.recyclarr = { };
  };
}