# /etc/nixos/hosts/yorke/configuration.nix
{ inputs, config, lib, pkgs, ... }: # Füge pkgs und lib hinzu, um sicherzustellen, dass sie da sind
{
  imports = [
    ./hardware-configuration.nix
  ];

  networking.hostName = "yorke";

  users.users.philipp = {
    isNormalUser = true;
    description = "Philipp Fleischer";
    extraGroups = [ "networkmanager" "wheel" "adbusers" ];
  };

  system.stateVersion = "24.05";

  my.nixos = {
    audio.pipewire.enable = true;
    desktop.gnome.enable = true;
  };
}