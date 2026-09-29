# features/system/locate/nixos.nix
#
# A file-name database for the fleet's interactive hosts. It is deliberately not part of any
# desktop feature: the desktop's search integration may use it, but a shell user without a desktop
# wants `locate` just the same. The previous home was the Niri module, which tied a general tool to
# one desktop environment.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.features.system.locate;
in
{
  options.my.features.system.locate = {
    enable = lib.mkEnableOption "the plocate file-name database";
  };

  config = lib.mkIf cfg.enable {
    services.locate = {
      enable = true;
      package = pkgs.plocate;
    };
  };
}
