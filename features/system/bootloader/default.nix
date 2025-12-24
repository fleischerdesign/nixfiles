# features/system/bootloader.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.my.features.system.bootloader;
in
{
  options.my.features.system.bootloader = {
    enable = lib.mkEnableOption "Bootloader configuration";
    provider = lib.mkOption {
      type = lib.types.enum [ "grub" "systemd-boot" ];
      default = "grub";
      description = "Which bootloader to use. Can be 'grub' or 'systemd-boot'.";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    # Common settings for all bootloaders
    {
      boot.loader.efi.canTouchEfiVariables = true;
      boot.kernelParams = [ "quiet" ];
    }

    # GRUB configuration
    (lib.mkIf (cfg.provider == "grub") {
      boot.loader.grub = {
        enable = true;
        device = "nodev"; # Universal for all EFI systems
        efiSupport = true;
        useOSProber = true; # Automatically find other OSes
        theme = pkgs.nixos-grub2-theme;
      };
      boot.loader.systemd-boot.enable = lib.mkForce false;
    })

    # systemd-boot configuration
    (lib.mkIf (cfg.provider == "systemd-boot") {
      boot.loader.systemd-boot = {
        enable = true;
        configurationLimit = 5; # Optional: Keep last 5 generations
      };
      boot.loader.grub.enable = lib.mkForce false;
    })
  ]);
}
