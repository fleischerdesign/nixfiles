{
  config,
  lib,
  ...
}:
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
  };

  config = lib.mkIf cfg.enable {
    services.caddy = {
      enable = true;

      # Authentik Snippet
      extraConfig = ''
        (authentik) {
          # Handle outpost paths (callback, sign_out, etc) directly
          handle /outpost.goauthentik.io/* {
            reverse_proxy 127.0.0.1:9000
          }
        }
      '';

      # Generate virtualHosts from service registry (local host only)
      virtualHosts =
        let
          localServices = lib.filterAttrs (
            _: svc:
            svc.host == config.networking.hostName
            && svc.caddy.enable
            && (svc.subdomain != null || svc.fullDomain != null)
          ) config.my.endpoints;

          mkVHost = _name: conf: {
            name = if conf.fullDomain != null then conf.fullDomain else "${conf.subdomain}.${cfg.baseDomain}";
            value = {
              extraConfig =
                if conf.auth then
                  ''
                    import authentik
                    handle {
                      forward_auth 127.0.0.1:9000 {
                        uri /outpost.goauthentik.io/auth/caddy
                        copy_headers X-Authentik-Username X-Authentik-Groups X-Authentik-Email X-Authentik-Name X-Authentik-Uid X-Authentik-Jwt X-Authentik-Meta-Jwks X-Authentik-Meta-Outpost X-Authentik-Meta-Provider X-Authentik-Meta-App X-Authentik-Meta-Version authorization
                        trusted_proxies private_ranges
                      }
                      reverse_proxy 127.0.0.1:${toString conf.port}
                    }
                  ''
                else
                  ''
                    reverse_proxy 127.0.0.1:${toString conf.port}
                  '';
            };
          };
        in
        lib.listToAttrs (lib.mapAttrsToList mkVHost localServices);
    };

    networking.firewall.allowedTCPPorts = [
      80
      443
    ];
    networking.firewall.allowedUDPPorts = [ 443 ]; # QUIC / HTTP/3

    # Allow group read access to logs (for CrowdSec and Alloy)
    systemd.services.caddy.serviceConfig.UMask = "0027";

    systemd.tmpfiles.rules = [
      "d /var/log/caddy 0755 caddy caddy -"
      "z /var/log/caddy/*.log 0640 caddy caddy -"
    ];
  };
}
