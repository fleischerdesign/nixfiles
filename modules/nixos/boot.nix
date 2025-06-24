{ config, lib, pkgs, ... }:
{
  options.my.nixos.boot.enable = lib.mkEnableOption "Boot config";

  config = lib.mkIf config.my.nixos.boot.enable {
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;
  };
}