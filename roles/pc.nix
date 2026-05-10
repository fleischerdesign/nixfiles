# roles/pc.nix
# This is the base role for any "Personal Computer", whether desktop or notebook.
{
  config,
  lib,
  inputs,
  pkgs,
  ...
}:

{
  programs.kdeconnect.enable = true;
  hardware.enableRedistributableFirmware = lib.mkDefault true;
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
      networking.ssh.enable = lib.mkDefault true;
      networking.topology.enable = lib.mkDefault true;
    };
  };

  environment.systemPackages = [
    inputs.deploy-rs.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
