{ config, lib, pkgs, ... }:
let
  cfg = config.my.features.services.recyclarr;
in
{
  options.my.features.services.recyclarr = {
    enable = lib.mkEnableOption "Recyclarr Configuration Sync";
  };

  config = lib.mkIf cfg.enable {
    # 1. SOPS secrets for API keys (must be owned by recyclarr)
    sops.secrets.radarr_api_key = { owner = "recyclarr"; };
    sops.secrets.sonarr_api_key = { owner = "recyclarr"; };

    # 2. Create environment file for Recyclarr to use the secrets
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
          
          # Prioritize German audio but allow English fallback
          custom_formats = [
            {
              names = [ "German" ];
              score = 100;
            }
          ];

          include = [
            # Standard TRaSH Quality Definitions
            { template = "radarr-quality-definition-movie"; }
            # Custom Formats for better releases (Removes CAMs, fake releases etc.)
            { template = "radarr-custom-formats-movie"; }
          ];
        };

        # Sonarr Configuration (TV Shows)
        sonarr.main = {
          base_url = "http://localhost:8989";
          api_key = "!env_var SONARR_API_KEY";

          # Prioritize German audio but allow English fallback
          custom_formats = [
            {
              names = [ "German" ];
              score = 100;
            }
          ];

          include = [
            # Standard TRaSH Quality Definitions for Series
            { template = "sonarr-quality-definition-series"; }
            # Custom Formats for Series (V3/V4 templates)
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