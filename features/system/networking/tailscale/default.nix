{ config, lib, pkgs, ... }:

let
  cfg = config.my.features.system.networking.tailscale;
in
{
  options.my.features.system.networking.tailscale = {
    enable = lib.mkEnableOption "Tailscale Mesh VPN";
    useSubnetRouter = lib.mkEnableOption "Advertise local subnet to Tailscale";
  };

  config = lib.mkIf cfg.enable {
    services.tailscale.enable = true;

    # Erlaubt Tailscale Traffic durch die Firewall
    networking.firewall.checkReversePath = "loose";
    networking.firewall.trustedInterfaces = [ "tailscale0" ];

    # Wenn Subnet Router aktiv ist, muss IP Forwarding an sein
    boot.kernel.sysctl = lib.mkIf cfg.useSubnetRouter {
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
    };
  };
}
