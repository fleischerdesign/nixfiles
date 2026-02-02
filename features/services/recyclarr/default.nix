{ config, lib, pkgs, ... }:
let
  cfg = config.my.features.services.recyclarr;
in
{
  options.my.features.services.recyclarr = {
    enable = lib.mkEnableOption "Recyclarr Configuration Sync";
  };

  config = lib.mkIf cfg.enable {
    # 1. Reuse existing SOPS secrets
    sops.secrets.radarr_api_key = { };
    sops.secrets.sonarr_api_key = { };

    # 2. Create the FULL configuration file via SOPS template
    sops.templates."recyclarr.yml" = {
      owner = "recyclarr";
      content = ''
        radarr:
          radarr-instance:
            base_url: http://localhost:7878
            api_key: ${config.sops.placeholder.radarr_api_key}
            
            quality_definition:
              type: movie

            custom_formats:
              - trash_ids: [86bc3115eb4e9873ac96904a4a68e19e] # German
                assign_scores_to:
                  - name: HD-1080p
                    score: 100
              - trash_ids: [f845be10da4f442654c13e1f2c3d6cd5] # German DL
                assign_scores_to:
                  - name: HD-1080p
                    score: 150

            quality_profiles:
              - name: HD-1080p
                upgrade:
                  default: true
                  until_score: 150
                min_format_score: 0

        sonarr:
          sonarr-instance:
            base_url: http://localhost:8989
            api_key: ${config.sops.placeholder.sonarr_api_key}

            quality_definition:
              type: series

            custom_formats:
              - trash_ids: [8a9fcdbb445f2add0505926df3bb7b8a] # German
                assign_scores_to:
                  - name: HD-1080p
                    score: 100
              - trash_ids: [ed51973a811f51985f14e2f6f290e47a] # German DL
                assign_scores_to:
                  - name: HD-1080p
                    score: 150

            quality_profiles:
              - name: HD-1080p
                upgrade:
                  default: true
                  until_score: 150
                min_format_score: 0
      '';
    };

    # 3. Recyclarr Service
    services.recyclarr = {
      enable = true;
      schedule = "daily";
      command = "sync --config ${config.sops.templates."recyclarr.yml".path}";
    };

    # Explicitly define user and group for SOPS
    users.users.recyclarr = {
      isSystemUser = true;
      group = "recyclarr";
    };
    users.groups.recyclarr = { };
  };
}