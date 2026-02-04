{ inputs, config, lib, pkgs, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./hardware-specific.nix
    ../../roles/notebook.nix
  ];

  networking.hostName = "yorke";

  users.users.philipp = {
    isNormalUser = true;
    description = "Philipp Fleischer";
    extraGroups = [
      "networkmanager"
      "wheel"
      "adbusers"
    ];
  };

  # Features
  my.features.desktop.niri.enable = true;
  my.features.desktop.quickshell.enable = true;

  my.features.dev.containers.enable = true;
  my.features.dev.containers.users = [ "philipp" ];
  my.features.dev.android.enable = true;
  my.features.dev.codium.enable = true;
  my.features.dev.nixvim.enable = true;

  my.features.media.spotify.enable = true;

  system.stateVersion = "24.05";
}