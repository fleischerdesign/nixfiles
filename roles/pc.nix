# roles/pc.nix
# This is the base role for any "Personal Computer", whether desktop or notebook.
{ lib, ... }:

{
  # It enables a baseline set of features common to all graphical systems.
  my.features = {
    common.enable = lib.mkDefault true;
    audio.enable = lib.mkDefault true;
    bootloader.enable = lib.mkDefault true;
    kernel.enable = lib.mkDefault true;
    wayland.enable = lib.mkDefault true;
    fish-shell.enable = lib.mkDefault true;
    printing.enable = lib.mkDefault true;
  };
}
