{
  config,
  lib,
  ...
}:

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
  };
}
