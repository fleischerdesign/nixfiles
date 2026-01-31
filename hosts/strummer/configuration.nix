{ pkgs, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./hardware-specific.nix
  ];

  networking.hostName = "strummer";

  # Define the user account
  users.users.philipp = {
    isNormalUser = true;
    description = "Philipp Fleischer";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB+bSErYniJev/+/UxsilaoxHGYW8oVpd3pYMQuuGStw fleis@Yorke"
    ];
  };

  # State version setting
  system.stateVersion = "24.11"; 

}
