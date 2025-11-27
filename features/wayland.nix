# features/wayland.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.my.features.wayland;
in
{
  options.my.features.wayland = {
    enable = lib.mkEnableOption "General Wayland settings";
  };

  config = lib.mkIf cfg.enable {
    # Wayland session variable for Electron apps
    environment.sessionVariables = {
      NIXOS_OZONE_WL = "1";
    };
  };
}
