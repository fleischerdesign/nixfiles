# roles/server.nix
# This role defines the default features for a headless server.
{ lib, ... }:

{
  my.role = "server";

  my.features = {
    system = {
      common.enable = lib.mkDefault true;
      bootloader = {
        enable = lib.mkDefault true;
        provider = lib.mkDefault "systemd-boot";
      };
      kernel.enable = lib.mkDefault true;
      fish-shell.enable = lib.mkDefault true;
      networking.topology.enable = lib.mkDefault true;
    };
  };

  my.features.system.networking.ssh.enable = lib.mkDefault true;
}
