{ config, lib, pkgs, ... }:
let
  cfg = config.my.features.system.networking.ssh;
  hosts = config.my.features.system.networking.topology.hosts;
  ownHost = hosts.${config.networking.hostName} or null;
  listenAddresses = lib.mkIf (ownHost != null) (
    lib.optional (ownHost.localIp != null) { addr = ownHost.localIp; port = 22; }
    ++ lib.optional (ownHost.tailscaleIp != null) { addr = ownHost.tailscaleIp; port = 22; }
  );
in
{
  options.my.features.system.networking.ssh = {
    enable = lib.mkEnableOption "SSH server, bound to LAN and Tailscale only";
  };

  config = lib.mkIf cfg.enable {
    my.features.system.networking.topology.enable = lib.mkDefault true;

    systemd.services.sshd.after = [ "network-online.target" ]
      ++ lib.optional config.services.tailscale.enable "tailscaled.service";

    services.openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = false;
      };
      listenAddresses = listenAddresses;
    };

    warnings = lib.optionals (cfg.enable && ownHost == null) [
      "SSH feature: host '${config.networking.hostName}' not found in topology — SSH will bind to all interfaces."
    ];
  };
}
