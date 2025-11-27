# features/system/bootloader.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.my.features.system.bootloader;
in
{
  options.my.features.system.bootloader = {
    enable = lib.mkEnableOption "Bootloader configuration (GRUB for EFI)";
  };

  config = lib.mkIf cfg.enable {
    boot.loader = {
      # GRUB for EFI systems
      grub = {
        enable = true;
        device = "nodev"; # Universal for all EFI systems
        efiSupport = true;
        useOSProber = true; # Automatically find other OSes

        # Optional: Nicer theme
        theme = pkgs.nixos-grub2-theme;
      };

      efi = {
        canTouchEfiVariables = true;
      };

      # Disable systemd-boot if you want to be sure
      systemd-boot.enable = lib.mkForce false;
    };

    boot.kernelParams = [ "quiet" ];
  };
}
