# features/media/spotify/home.nix - the per-user half of the Spotify/Spicetify feature.
{ inputs, pkgs, ... }:
let
  spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in
{
  imports = [ inputs.spicetify-nix.homeManagerModules.default ];

  programs.spicetify = {
    enable = true;
    wayland = true;
    theme = spicePkgs.themes.dribbblishDynamic;
  };
}
