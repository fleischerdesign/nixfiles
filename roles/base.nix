# roles/base.nix
# Base system configurations applicable to all hosts (servers and personal computers).
{lib, ...}: {
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
