# roles/server.nix
# This role defines the default features for a headless server.
{ lib, ... }:

{
  my.features = {
    system = {
      common.enable = lib.mkDefault true;
      bootloader = {
        enable = lib.mkDefault true;
        provider = lib.mkDefault "systemd-boot";
      };
      kernel.enable = lib.mkDefault true;
      fish-shell.enable = lib.mkDefault true;
    };
  };

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };

  sops.age.keyFile = "/etc/ssh/ssh_host_ed25519_key";
}
