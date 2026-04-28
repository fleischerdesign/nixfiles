{ config, lib, pkgs, ... }:

let
  cfg = config.my.features.system.networking.tailscale;
in
{
  options.my.features.system.networking.tailscale = {
    enable = lib.mkEnableOption "Tailscale Mesh VPN";
    subnetRouter = {
      enable = lib.mkEnableOption "Tailscale subnet router";
      routes = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Routes to advertise to the Tailscale network";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.tailscale.enable = true;
    services.tailscale.extraUpFlags = lib.mkIf cfg.subnetRouter.enable [
      "--advertise-routes=${lib.concatStringsSep "," cfg.subnetRouter.routes}"
    ];

    # Erlaubt Tailscale Traffic durch die Firewall
    networking.firewall.checkReversePath = "loose";
    networking.firewall.trustedInterfaces = [ "tailscale0" ];

    # Wenn Subnet Router aktiv ist, muss IP Forwarding an sein
    boot.kernel.sysctl = lib.mkIf cfg.subnetRouter.enable {
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
    };
  };
}
