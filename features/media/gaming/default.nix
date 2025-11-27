# features/media/gaming.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.my.features.media.gaming;
in
{
  options.my.features.media.gaming = {
    enable = lib.mkEnableOption "Gaming packages and services (Steam, Lutris, Sunshine)";
  };

  config = lib.mkIf cfg.enable {
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
        extraLibraries = pkgs: with pkgs; [
          libadwaita
          gtk4
        ];
      })
      umu-launcher
    ];
  };
}
