# /etc/nixos/hosts/yorke/configuration.nix
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

  system.stateVersion = "24.05";

  # Features are enabled in `metadata.nix`.
  # This file is for host-specific overrides.
}
