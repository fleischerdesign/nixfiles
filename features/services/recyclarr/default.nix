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
    # This avoids the "!env_var" string vs tag issue entirely.
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
                  - name: HD - 1080p
                    score: 100

        sonarr:
          sonarr-instance:
            base_url: http://localhost:8989
            api_key: ${config.sops.placeholder.sonarr_api_key}
            quality_definition:
              type: series
            custom_formats:
              - trash_ids: [8a9fcdbb445f2add0505926df3bb7b8a] # German
                assign_scores_to:
                  - name: HD - 1080p
                    score: 100
      '';
    };

    # 3. Recyclarr Service
    services.recyclarr = {
      enable = true;
      schedule = "daily";
      # We override the command to point to our secret config file
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
