{
  lib,
  ...
}:
{
  my.features.system.bootloader.enable = lib.mkForce false;
  boot.loader.grub.enable = true;
  boot.loader.grub.devices = lib.mkForce [ "/dev/vda" ];
}
