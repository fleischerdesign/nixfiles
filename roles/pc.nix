# roles/pc.nix
# This is the base role for any "Personal Computer", whether desktop or notebook.
{
  lib,
  inputs,
  pkgs,
  ...
}: {
  imports = [
    ./base.nix
  ];

  hardware.enableRedistributableFirmware = lib.mkDefault true;

  # It enables a baseline set of features common to all graphical systems.
  my.features.system = {
    audio.enable = lib.mkDefault true;
    wayland.enable = lib.mkDefault true;
    printing.enable = lib.mkDefault true;
  };

  services.xserver.xkb.layout = lib.mkDefault "de";

  environment.systemPackages = [
    inputs.deploy-rs.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
