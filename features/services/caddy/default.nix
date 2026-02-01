{ config, lib, pkgs, ... }:
let
  cfg = config.my.features.services.caddy;
in
{
  options.my.features.services.caddy.enable = lib.mkEnableOption "Caddy Web Server";

  config = lib.mkIf cfg.enable {
    services.caddy = {
      enable = true;
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
    };

    networking.firewall.allowedTCPPorts = [ 80 443 ];
    networking.firewall.allowedUDPPorts = [ 443 ]; # QUIC / HTTP/3
  };
}
