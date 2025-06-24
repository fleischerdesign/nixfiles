{ config, lib, pkgs, ... }:
{
  options.my.nixos.gaming.enable = lib.mkEnableOption "Gaming packages and services";

  config = lib.mkIf config.my.nixos.gaming.enable {
    programs.steam = {
      enable = true;
      remotePlay.openFirewall = true;
      dedicatedServer.openFirewall = true;
      localNetworkGameTransfers.openFirewall = true;
    };

    services.sunshine = {
      enable = true;
      autoStart = true;
      capSysAdmin = true;
      openFirewall = true;
    };

    environment.systemPackages = with pkgs; [
      winetricks
      wine
      lutris
      umu-launcher
    ];
  };
}