# features/desktop/anytype/nixos.nix - the system half of the Anytype desktop feature.
{
  config,
  lib,
  ...
}:

let
  cfg = config.my.features.desktop.anytype;
in
{
  options.my.features.desktop.anytype = {
    enable = lib.mkEnableOption "Anytype desktop client";
  };

  config = lib.mkIf cfg.enable {
    # The client is a per-user package; the system side stays the switch that registers it.
    home-manager.sharedModules = [ ./home.nix ];
  };
}
