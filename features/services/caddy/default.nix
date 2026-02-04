{ config, lib, pkgs, ... }:
let
  cfg = config.my.features.services.caddy;
in
{
  options.my.features.services.caddy = {
    enable = lib.mkEnableOption "Caddy Web Server";
    
    baseDomain = lib.mkOption {
      type = lib.types.str;
      description = "Base domain for exposed services (e.g. fls.ancoris.ovh)";
    };

    exposedServices = lib.mkOption {
      description = "Services to expose via Caddy";
      default = {};
      type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
        options = {
          port = lib.mkOption { type = lib.types.int; };
          auth = lib.mkEnableOption "Protect with Authentik";
          subdomain = lib.mkOption {
            type = lib.types.str;
            default = name; # Default: Use the attribute name
          };
          fullDomain = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Override the entire domain (bypasses subdomain and baseDomain)";
          };
        };
      }));
    };
  };

  config = lib.mkIf cfg.enable {
    services.caddy = {
      enable = true;
      
      # Authentik Snippet
      extraConfig = ''
        (authentik) {
          reverse_proxy /outpost.goauthentik.io/* 127.0.0.1:9000
          forward_auth 127.0.0.1:9000 {
            uri /outpost.goauthentik.io/auth/caddy
            copy_headers X-Authentik-Username X-Authentik-Groups X-Authentik-Email X-Authentik-Name X-Authentik-Uid X-Authentik-Jwt X-Authentik-Meta-Jwks X-Authentik-Meta-Outpost X-Authentik-Meta-Provider X-Authentik-Meta-App X-Authentik-Meta-Version authorization
            trusted_proxies private_ranges
          }
        }
      '';

      # Generate virtualHosts from exposedServices
      virtualHosts = 
        let
          mkVHost = name: conf: {
            name = if conf.fullDomain != null then conf.fullDomain else "${conf.subdomain}.${cfg.baseDomain}";
            value = {
              extraConfig = ''
                reverse_proxy 127.0.0.1:${toString conf.port}
                ${lib.optionalString conf.auth "import authentik"}
              '';
            };
          };
        in
        lib.listToAttrs (lib.mapAttrsToList mkVHost cfg.exposedServices);
    };

    networking.firewall.allowedTCPPorts = [ 80 443 ];
    networking.firewall.allowedUDPPorts = [ 443 ]; # QUIC / HTTP/3

    # Allow group read access to logs (for CrowdSec and Promtail)
    systemd.services.caddy.serviceConfig.UMask = "0027";

    systemd.tmpfiles.rules = [
      "d /var/log/caddy 0755 caddy caddy -"
      "z /var/log/caddy/*.log 0640 caddy caddy -"
    ];
  };
}