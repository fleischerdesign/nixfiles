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
        # Network configuration
        ports.dns = 53; # Standard DNS port
        host = "0.0.0.0";

        # Upstream DNS (using DNS-over-HTTPS for privacy)
        upstream.default = [
          "https://one.one.one.one/dns-query"
          "https://dns.google/dns-query"
        ];

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
          # If a site is blocked, return an IP that simply doesn't respond
          # instead of 0.0.0.0 (often faster for browsers)
          blockType = "zeroIp";
        };

        # Redis Caching (using your existing Redis feature)
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

        # Enable Prometheus metrics (handy for future dashboards)
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
