# features/system/backups/restic/default.nix
# Declarative automated Restic backup feature module with SOPS credentials integration.
{
  config,
  lib,
  ...
}:

let
  cfg = config.my.features.system.backups.restic;
in
{
  options.my.features.system.backups.restic = {
    enable = lib.mkEnableOption "Restic automated encrypted backups";

    paths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "/var/lib"
        "/etc/nixos"
      ];
      description = "List of filesystem paths to include in the daily backup snapshot.";
    };

    exclude = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "**/node_modules"
        "**/.cache"
        "/var/lib/docker"
      ];
      description = "List of file patterns or directories to exclude from backup snapshots.";
    };

    environmentFile = lib.mkOption {
      type = lib.types.str;
      description = "Name of the SOPS secret containing environment variables for Restic repository credentials.";
      example = "restic_environment_strummer";
    };
  };

  config = lib.mkIf cfg.enable {
    services.restic.backups.daily = {
      inherit (cfg) paths exclude;

      environmentFile = config.sops.secrets."${cfg.environmentFile}".path;

      timerConfig = {
        OnCalendar = "03:00";
        RandomizedDelaySec = "1h";
      };

      pruneOpts = [
        "--keep-daily 7"
        "--keep-weekly 4"
        "--keep-monthly 6"
      ];

      initialize = true;
    };

    sops.secrets."${cfg.environmentFile}" = { };
  };
}
