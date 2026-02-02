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