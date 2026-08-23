# roles/base.nix
# Base system configurations applicable to all hosts (servers and personal computers).
{ config, lib, ... }: {
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
      security.enable = lib.mkDefault true;
    };
  };

  my.features.system.networking.ssh.enable = lib.mkDefault true;

  nod = {
    enable = lib.mkDefault true;
    targetHost = lib.mkDefault (
      config.my.features.system.networking.topology.hosts.${config.networking.hostName}.tailscaleIp
        or config.networking.hostName
    );
    role = lib.mkDefault config.my.role;
    tags = lib.mkDefault [ ];
    ssh = {
      user = lib.mkDefault "root";
      identityFile = lib.mkDefault "~/.ssh/deploy-key";
    };
    healthChecks = {
      enable = lib.mkDefault true;
      systemd = {
        checkRunning = lib.mkDefault true;
        checkFailedUnits = lib.mkDefault true;
      };
    };
  };
}
