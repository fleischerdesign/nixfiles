# features/dev/codium.nix
{
  config,
  lib,
  ...
}:

let
  cfg = config.my.features.dev.codium;
in
{
  options.my.features.dev.codium = {
    enable = lib.mkEnableOption "VSCodium with extensions";
  };

  config = lib.mkIf cfg.enable {
    home-manager.sharedModules = [ ./home.nix ];
  };
}
