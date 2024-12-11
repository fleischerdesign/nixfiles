{ pkgs, ... }:
{
  home.packages = [
    pkgs.google-chrome
    pkgs.spotify
    pkgs.gnomeExtensions.blur-my-shell
    pkgs.gnomeExtensions.gsconnect
    pkgs.gnomeExtensions.caffeine
    pkgs.gnomeExtensions.dash-to-dock
    pkgs.gimp
    pkgs.blackbox-terminal
    pkgs.figma-linux
    pkgs.obsidian
    pkgs.orca-slicer
    pkgs.nixd
    pkgs.nixfmt-rfc-style
    pkgs.endeavour
    (pkgs.callPackage ../../packages/lychee-slicer { })
  ];
}