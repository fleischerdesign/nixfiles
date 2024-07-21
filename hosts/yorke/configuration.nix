{ config, pkgs, inputs, ... }:

{
  imports =
    [ ./hardware-configuration.nix
      ../default.nix
      ../../modules/audio.nix
      ../../modules/gnome.nix
    ];

  # Define the hosstname
  networking.hostName = "yorke";

  # Enable CUPS to print documents
  services.printing.enable = true;

  # Home Manager settings
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.users.philipp = inputs.self.hmModules.philipp;

  # Define the user account
  users.users.philipp = {
    isNormalUser = true;
    description = "Philipp Fleischer";
    extraGroups = [ "networkmanager" "wheel" "adbusers"];
  };

  # State version setting
  system.stateVersion = "24.05"; # Keep this to match your initial install
}

