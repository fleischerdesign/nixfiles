{ config, lib, pkgs, ... }:
let
  cfg = config.my.features.services.blocky;
in
{
  options.my.features.services.blocky = {
    enable = lib.mkEnableOption "Blocky DNS Ad-blocker";
  };

  config = lib.mkIf cfg.enable {
    services.blocky = {
      enable = true;
      settings = {
        # Network configuration - Blocky expects the port or address:port
        ports.dns = 53; 
        ports.http = 4000; # Port for metrics and API

        # Upstream DNS (using DNS-over-HTTPS for privacy)
        upstream.default = [
          "https://one.one.one.one/dns-query"
          "https://dns.google/dns-query"
        ];

        # Conditional DNS Mapping (Split DNS)
        # Geräte im Heimnetz (192.168.178.0/24) bekommen lokale IPs,
        # alle anderen (Tailscale-Clients) bekommen Tailscale-IPs
        conditional = {
          mapping =
            let
              hosts = config.my.features.system.networking.topology.hosts;
              isInHomeNetwork = ip: lib.hasPrefix "192.168.178." ip;
              mkHostMapping = host:
                if host.localIp != null && host.tailscaleIp != null && isInHomeNetwork host.localIp
                then [
                  { for = [ "192.168.178.0/24" ]; answer = host.localIp; }
                  { answer = host.tailscaleIp; }
                ]
                else [
                  { answer = if host.tailscaleIp != null then host.tailscaleIp else host.localIp; }
                ];
            in
            lib.mapAttrs' (name: host: {
              name = host.domain;
              value = mkHostMapping host;
            }) (lib.filterAttrs (name: host: host.domain != null) hosts);
        };

        # Ad-blocking configuration
        blocking = {
          blackLists = {
            ads = [
              "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
            ];
          };
          clientGroupsBlock = {
            default = [ "ads" ];
          };
          blockType = "zeroIp";
        };

        # Redis Caching
        redis = {
          address = "localhost:6379";
          database = 0;
        };

        # Caching settings
        caching = {
          minTime = "5m";
          maxTime = "30m";
          prefetching = true;
        };

        # Enable Prometheus metrics
        prometheus = {
          enable = true;
          path = "/metrics";
        };
      };
    };

    # Open DNS ports in the firewall
    networking.firewall.allowedUDPPorts = [ 53 ];
    networking.firewall.allowedTCPPorts = [ 53 ];
  };
}