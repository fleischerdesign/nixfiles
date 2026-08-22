# roles/pc.nix
# This is the base role for any "Personal Computer", whether desktop or notebook.
{
  lib,
  ...
}:
{
  imports = [
    ./base.nix
  ];

  hardware.enableRedistributableFirmware = lib.mkDefault true;

  my.user.extraGroups = lib.mkDefault [
    "networkmanager"
    "wheel"
    "adbusers"
    "input"
    "uinput"
  ];

  # It enables a baseline set of features common to all graphical systems.
  my.features.system = {
    audio.enable = lib.mkDefault true;
    wayland.enable = lib.mkDefault true;
    printing.enable = lib.mkDefault true;
  };

  my.features.desktop = {
    webapps.enable = lib.mkDefault true;
  };

  my.features.dev = {
    containers.enable = lib.mkDefault true;
    codium.enable = lib.mkDefault true;
    nixvim.enable = lib.mkDefault true;
    obsidian.enable = lib.mkDefault true;
  };

  my.features.media = {
    gaming.enable = lib.mkDefault true;
    spotify.enable = lib.mkDefault true;
  };

  services.xserver.xkb.layout = lib.mkDefault "de";
}
