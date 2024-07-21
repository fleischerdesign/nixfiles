{ config, pkgs, inputs, ... }:

{
  imports =
    [ ./hardware-configuration.nix
      ../default.nix
      ../../modules/audio.nix
      ../../modules/gnome.nix
    ];

  # Define the hosstname
  networking.hostName = "jello";

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
    extraGroups = [ "networkmanager" "wheel" "adbusers" ];
  };

  # Enable ADB and Steam with firewall settings
  programs.adb.enable = true;
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
    localNetworkGameTransfers.openFirewall = true;
  };

  # State version setting
  system.stateVersion = "24.05"; # Keep this to match your initial install

}
