{ config, lib, pkgs, ... }:

{
  # Disable the generic bootloader feature from role/server (which enforces systemd-boot)
  my.features.system.bootloader.enable = lib.mkForce false;

  # Bootloader Configuration
  # Most vServers use BIOS/MBR boot with GRUB.
  boot.loader.grub.enable = true;
  boot.loader.grub.devices = lib.mkForce [ "/dev/sda" ]; # Matches sda from lsblk
  
  # If UEFI is supported:
  # boot.loader.systemd-boot.enable = true;
  # boot.loader.efi.canTouchEfiVariables = true;
}
