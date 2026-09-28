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
      # `mkDefault` because the dormant Niri module still declares the same package; while both
      # existed, one had to yield, and the generic tool belongs to this feature, not to a desktop.
      # The value is identical either way - this only decides who is allowed to state it.
      package = lib.mkDefault pkgs.plocate;
    };
  };
}
