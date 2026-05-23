{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.features.system.networking.tailscale;

  topology = config.my.features.system.networking.topology;
  topologyEnabled = config.my.features.system.networking.topology.enable or false;
  hostName = config.networking.hostName;
  localIp = if topologyEnabled then topology.hosts.${hostName}.localIp or null else null;
  isOnLocalSubnet = localIp != null && lib.hasPrefix "192.168.178." localIp;
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
    acceptRoutes = lib.mkEnableOption "Accept subnet routes from other Tailscale peers";
  };

  config = lib.mkIf cfg.enable {
    services.tailscale.enable = true;

    services.tailscale.useRoutingFeatures =
      if cfg.subnetRouter.enable && cfg.acceptRoutes then
        "both"
      else if cfg.subnetRouter.enable then
        "server"
      else if cfg.acceptRoutes then
        "client"
      else
        "none";

    services.tailscale.extraSetFlags =
      lib.optionals cfg.subnetRouter.enable [
        "--advertise-routes=${lib.concatStringsSep "," cfg.subnetRouter.routes}"
      ]
      ++ lib.optionals cfg.acceptRoutes [
        "--accept-routes"
      ];

    networking.firewall.checkReversePath = "loose";
    networking.firewall.trustedInterfaces = [ "tailscale0" ];

    systemd.services.tailscale-ensure-local-subnet = lib.mkIf (cfg.acceptRoutes && isOnLocalSubnet) {
      description = "Route local subnet traffic via physical interface, not Tailscale tunnel";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network-online.target"
        "tailscaled.service"
      ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.iproute2}/bin/ip rule add to 192.168.178.0/24 lookup main priority 500";
        ExecStop = "${pkgs.iproute2}/bin/ip rule del to 192.168.178.0/24 lookup main priority 500";
      };
    };
  };
}
