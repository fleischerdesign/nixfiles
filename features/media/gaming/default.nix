# features/media/gaming.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.my.features.media.gaming;
in
{
  options.my.features.media.gaming = {
    enable = lib.mkEnableOption "Gaming packages and services (Steam, Bottles, Sunshine)";
    sunshine.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to enable the Sunshine streaming host.";
    };
  };

  config = lib.mkIf cfg.enable {
    my.features.system.audio.enable = true;

    programs.steam = {
      enable = true;
      remotePlay.openFirewall = true;
      dedicatedServer.openFirewall = true;
      localNetworkGameTransfers.openFirewall = true;
    };

    services.sunshine = lib.mkIf cfg.sunshine.enable {
      enable = true;
      autoStart = true;
      capSysAdmin = true;
      openFirewall = true;
    };

    environment.systemPackages = with pkgs; [
      bottles
    ];
  };
}
