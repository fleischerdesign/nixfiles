# features/system/backups/restic/nixos.nix
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
      default = "backups/restic/${config.networking.hostName}";
      description = "Name of the SOPS secret containing environment variables for Restic repository credentials.";
      example = "backups/restic/hom-srv-01";
    };

    declined = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Reason this host deliberately runs no backup. It is what turns "restic was not enabled" into a
        decision the backup contract can read: a host that declares restorable state, runs no backup and
        gives no reason fails the build instead of looking like a host somebody forgot.
      '';
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
