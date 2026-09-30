{ config, lib, ... }:
let
  cfg = config.my.features.system.rclone;
in
{
  options.my.features.system.rclone.enable = lib.mkEnableOption "user-scoped rclone mounts";
  config = {
    home-manager.sharedModules = [ ./home.nix ];
    programs.fuse.enable = lib.mkIf cfg.enable true;
    assertions = [
      {
        assertion =
          !cfg.enable
          || lib.elem config.my.role [
            "desktop"
            "notebook"
          ];
        message = "rclone mounts are enabled only on PC roles, never on servers.";
      }
    ];
  };
}
