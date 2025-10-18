{ config, lib, pkgs, inputs, ... }:
let
  spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.stdenv.system};
in
{
  config = lib.mkIf config.my.homeManager.modules.spotify.enable {
    programs.spicetify = {
      enable = true;
      wayland = true;
      theme = spicePkgs.themes.catppuccin;
    };
  };
}
