{ config, lib, pkgs, ... }:
{
  options.my.nixos.gaming.gaming.enable = lib.mkEnableOption "Gaming packages and services";

  config = lib.mkIf config.my.nixos.gaming.gaming.enable {
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
      (lutris.override {
        # Adding libadwaita and gtk4 as extra libraries, so that winetricks will launch without errors inside lutris
        extraLibraries = pkgs: with pkgs; [
          libadwaita
          gtk4
        ];
      })
      umu-launcher
    ];
  };
}