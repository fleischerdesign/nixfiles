{ config, lib, pkgs, ... }:

{
  # Bootloader Configuration
  # Most vServers use BIOS/MBR boot with GRUB.
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda"; # Matches sda from lsblk
  
  # If UEFI is supported:
  # boot.loader.systemd-boot.enable = true;
  # boot.loader.efi.canTouchEfiVariables = true;
}
