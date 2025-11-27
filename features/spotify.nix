# features/spotify.nix
{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.my.features.spotify;
  spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.stdenv.system};
in
{
  options.my.features.spotify = {
    enable = lib.mkEnableOption "Spotify with Spicetify";
  };

  config = lib.mkIf cfg.enable {
    # This feature is purely for Home Manager.
    # It injects its configuration into all users that get this feature.
    home-manager.sharedModules = [{
      programs.spicetify = {
        enable = true;
        wayland = true;
        theme = spicePkgs.themes.dribbblishDynamic;
      };
    }];
  };
}
