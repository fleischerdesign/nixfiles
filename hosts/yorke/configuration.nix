{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:
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
      "input"
      "uinput"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB+bSErYniJev/+/UxsilaoxHGYW8oVpd3pYMQuuGStw fleis@Yorke"
    ];
  };

  # Features
  my.features.desktop.niri.enable = true;

  my.features.dev.containers.enable = true;
  my.features.dev.containers.users = [ "philipp" ];
  my.features.dev.android.enable = true;
  my.features.dev.codium.enable = true;
  my.features.dev.nixvim.enable = true;

  my.features.media.spotify.enable = true;
  my.features.media.gaming.enable = true;
  my.features.media.gaming.sunshine.enable = false;
  my.features.system.networking.tailscale.enable = true;

  system.stateVersion = "24.05";
}
