# features/dev/nixvim.nix
{
  config,
  lib,
  ...
}:

let
  cfg = config.my.features.dev.nixvim;
in
{
  options.my.features.dev.nixvim = {
    enable = lib.mkEnableOption "NixVim configuration";
  };

  config = lib.mkIf cfg.enable {
    home-manager.sharedModules = [ ./home.nix ];
  };
}
