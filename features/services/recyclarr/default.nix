{ config, lib, pkgs, ... }:
let
  cfg = config.my.features.services.recyclarr;
in
{
  options.my.features.services.recyclarr = {
    enable = lib.mkEnableOption "Recyclarr Configuration Sync";
  };

  config = lib.mkIf cfg.enable {
    # 1. SOPS secrets for API keys
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

    # 3. Recyclarr Service Configuration
    services.recyclarr = {
      enable = true;
      schedule = "daily";
      
      configuration = {
        # Radarr Configuration (Movies)
        radarr.main = {
          base_url = "http://localhost:7878";
          api_key = "!env_var RADARR_API_KEY";
          
          # Prioritize German audio using TRaSH ID
          custom_formats = [
            {
              trash_ids = [ "9b6a2b695ca61047fa3930f85524eb27" ]; # German
              assign_scores_to = [
                { name = "HD - 1080p"; score = 100; }
              ];
            }
          ];

          include = [
            { template = "radarr-quality-definition-movie"; }
            { template = "radarr-custom-formats-movie"; }
          ];
        };

        # Sonarr Configuration (TV Shows)
        sonarr.main = {
          base_url = "http://localhost:8989";
          api_key = "!env_var SONARR_API_KEY";

          # Prioritize German audio using TRaSH ID
          custom_formats = [
            {
              trash_ids = [ "5893f30ca06ed66df00be0bd00efcf95" ]; # German
              assign_scores_to = [
                { name = "HD - 1080p"; score = 100; }
              ];
            }
          ];

          include = [
            { template = "sonarr-quality-definition-series"; }
            { template = "sonarr-custom-formats-series"; }
          ];
        };
      };
    };

    # Inject environment variables into the systemd service
    systemd.services.recyclarr.serviceConfig.EnvironmentFile = config.sops.templates."recyclarr.env".path;

    # Explicitly define user and group to avoid evaluation issues
    users.users.recyclarr = {
      isSystemUser = true;
      group = "recyclarr";
    };
    users.groups.recyclarr = { };
  };
}