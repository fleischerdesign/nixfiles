{ pkgs, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./hardware-specific.nix
  ];

  # Define the hosstname
  networking.hostName = "jello";

  # Define the user account
  users.users.philipp = {
    isNormalUser = true;
    description = "Philipp Fleischer";
    extraGroups = [
      "networkmanager"
      "wheel"
      "adbusers"
    ];
  };

  # Features are enabled in `metadata.nix`.
  # This file is for host-specific overrides.

  # State version setting
  system.stateVersion = "24.05"; # Keep this to match your initial install

}
