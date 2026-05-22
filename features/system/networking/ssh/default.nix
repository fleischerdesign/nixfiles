{
  config,
  lib,
  ...
}:
let
  cfg = config.my.features.system.networking.ssh;
  hosts = config.my.features.system.networking.topology.hosts;
  ownHost = hosts.${config.networking.hostName} or null;
  userLib = import ../../../../lib/users.nix;
  listenAddresses = lib.mkIf (ownHost != null) (
    lib.optional (ownHost.localIp != null) {
      addr = ownHost.localIp;
      port = 22;
    }
    ++ lib.optional (ownHost.tailscaleIp != null) {
      addr = ownHost.tailscaleIp;
      port = 22;
    }
  );
in
{
  options.my.features.system.networking.ssh = {
    enable = lib.mkEnableOption "SSH server, bound to LAN and Tailscale only";
  };

  config = lib.mkIf cfg.enable {
    my.features.system.networking.topology.enable = lib.mkDefault true;

    systemd.services.sshd = {
      after = [
        "network-online.target"
      ]
      ++ lib.optional config.services.tailscale.enable "tailscaled.service";
      wants = [ "network-online.target" ];
    };

    services.openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "prohibit-password";
        PasswordAuthentication = false;
      };
      listenAddresses = listenAddresses;
    };

    users.users.root.openssh.authorizedKeys.keys = userLib.deploy.sshKeys;

    warnings = lib.optionals (cfg.enable && ownHost == null) [
      "SSH feature: host '${config.networking.hostName}' not found in topology — SSH will bind to all interfaces."
    ];
  };
}
