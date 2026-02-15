{ config, lib, pkgs, ... }:

let
  cfg = config.my.features.system.backups.restic;
in
{
  options.my.features.system.backups.restic = {
    enable = lib.mkEnableOption "restic";
    
    paths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "/var/lib" "/etc/nixos" ];
    };

    exclude = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "**/node_modules" "**/.cache" "/var/lib/docker" ];
    };

    environmentFile = lib.mkOption {
      type = lib.types.str;
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
