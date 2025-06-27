{ pkgs, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # Define the hosstname
  networking.hostName = "jello";

  # Home Manager settings
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.users.philipp = inputs.self.hmModules.philipp;

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
  
  programs.adb.enable = true;

  my.nixos = {
    audio.pipewire.enable = true;
    desktop.gnome.enable = true;
    gaming.enable = true;
  };

  # State version setting
  system.stateVersion = "24.05"; # Keep this to match your initial install

}
