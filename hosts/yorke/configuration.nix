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

  # Enable the X11 windowing system and desktop environment
  services.xserver.enable = true;
  services.xserver.displayManager.gdm = {
    enable = true;
    wayland = true;
  };
  services.xserver.desktopManager.gnome.enable = true;

  # Configure keymap in X11
  services.xserver.xkb.layout = "de";
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

