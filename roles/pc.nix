# roles/pc.nix
# This is the base role for any "Personal Computer", whether desktop or notebook.
{ lib, ... }:

{
  # It enables a baseline set of features common to all graphical systems.
  my.features = {
    system = {
      common.enable = lib.mkDefault true;
      audio.enable = lib.mkDefault true;
            bootloader = {
        enable = lib.mkDefault true;
        provider = lib.mkDefault "systemd-boot";
      };
      kernel.enable = lib.mkDefault true;
      wayland.enable = lib.mkDefault true;
      fish-shell.enable = lib.mkDefault true;
      printing.enable = lib.mkDefault true;
    };
  };
}
