{
  config,
  lib,
  pkgs,
  ...
}:
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

        # Bootstrap DNS — bricht den DNS-Loop (Blocky → System-Resolver → MagicDNS → Blocky)
        # Löst DoH-Upstream-Hostnames via Plain-DNS auf, ohne den System-Resolver zu nutzen
        bootstrapDns = [
          { upstream = "1.1.1.1"; }
          { upstream = "9.9.9.9"; }
        ];

        # Custom DNS Mapping (Split DNS)
        # Subdomains werden automatisch mit aufgelöst (Blocky-Feature)
        # Heimnetz-Hosts: lokale IP (via LAN oder Subnet-Router)
        # Externe Hosts (mackaye): Tailscale-IP (lokale IP nicht erreichbar)
        customDNS = {
          mapping = lib.mapAttrs' (name: host: {
            name = host.domain;
            value =
              if host.localIp != null && lib.hasPrefix "192.168.178." host.localIp then
                host.localIp
              else if host.tailscaleIp != null then
                host.tailscaleIp
              else
                host.localIp;
          }) config.my.features.system.networking.topology.hosts;
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
