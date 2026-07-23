{
  config,
  lib,
  pkgs,
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
    homeGatewayMac = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "44:4e:6d:15:62:5f";
      description = "Unique Layer-2 MAC address of home router for local network verification";
    };
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

    networking.networkmanager.dispatcherScripts = lib.mkIf (cfg.acceptRoutes && cfg.homeGatewayMac != null) [
      {
        source = pkgs.writeShellScript "tailscale-home-network-verifier" ''
          IFACE="$1"
          ACTION="$2"

          if [ "$IFACE" = "tailscale0" ] || [ "$IFACE" = "lo" ]; then
            exit 0
          fi

          case "$ACTION" in
            up|dhcp4-change)
              if ${pkgs.iproute2}/bin/ip addr show dev "$IFACE" 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q "192.168.178."; then
                GW_INFO=$(${pkgs.iproute2}/bin/ip neighbor show 192.168.178.1 dev "$IFACE" 2>/dev/null)
                if ! echo "$GW_INFO" | ${pkgs.gnugrep}/bin/grep -qi "${cfg.homeGatewayMac}"; then
                  ${pkgs.iputils}/bin/arping -c 2 -w 2 -I "$IFACE" 192.168.178.1 >/dev/null 2>&1 || true
                  GW_INFO=$(${pkgs.iproute2}/bin/ip neighbor show 192.168.178.1 dev "$IFACE" 2>/dev/null)
                fi

                if echo "$GW_INFO" | ${pkgs.gnugrep}/bin/grep -qi "${cfg.homeGatewayMac}"; then
                  ${pkgs.iproute2}/bin/ip rule del priority 500 2>/dev/null || true
                  ${pkgs.iproute2}/bin/ip rule add to 192.168.178.0/24 lookup main priority 500
                else
                  ${pkgs.iproute2}/bin/ip rule del priority 500 2>/dev/null || true
                fi
              fi
              ;;
            down)
              if ! ${pkgs.iproute2}/bin/ip addr show 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q "192.168.178."; then
                ${pkgs.iproute2}/bin/ip rule del priority 500 2>/dev/null || true
              fi
              ;;
          esac
        '';
      }
    ];
  };
}
