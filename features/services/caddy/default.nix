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
      description = "Base domain for exposed services (e.g. srv.lan.vyrx.de, edge.vyrx.de)";
    };

    authentikOutpostAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:9000";
      description = "Local socket address of the Authentik outpost proxy.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.caddy = {
      enable = true;

      # Authentik & Error Handling Snippets (DESIGN.md 7)
      extraConfig = ''
        (vyrx_errors) {
          handle_errors {
            rewrite * /errors/{err.status_code}.html
            file_server {
              root /etc/vyrx/theme
            }
          }
        }

        (authentik) {
          # Handle outpost paths (callback, sign_out, etc) directly
          handle /outpost.goauthentik.io/* {
            reverse_proxy ${cfg.authentikOutpostAddress}
          }
        }
      '';

      # Generate virtualHosts from service registry (local host only)
      virtualHosts =
        let
          localServices = lib.filterAttrs (
            _: svc: svc.host == config.networking.hostName && svc.proxy.enable && svc.canonicalDomain != null
          ) config.my.endpoints;

          mkVHost = _name: conf: {
            name = conf.canonicalDomain;
            value = {
              extraConfig =
                let
                  target = "127.0.0.1:${toString conf.port}";

                  exemptHandlers =
                    lib.optionalString (conf.proxy.unauthenticatedPaths != [ ]) ''
                      @unauthenticatedRoute path ${lib.concatStringsSep " " conf.proxy.unauthenticatedPaths}
                      handle @unauthenticatedRoute {
                        reverse_proxy ${target}
                      }
                    ''
                    + lib.optionalString conf.proxy.machineClientsBypassAuth ''
                      @nonBrowserWebsocket {
                        header Connection *Upgrade*
                        header Upgrade websocket
                        not header Origin *
                      }
                      handle @nonBrowserWebsocket {
                        reverse_proxy ${target}
                      }
                    '';
                in
                if conf.proxy.auth then
                  ''
                    import authentik
                    ${exemptHandlers}
                    handle {
                      forward_auth ${cfg.authentikOutpostAddress} {
                        uri /outpost.goauthentik.io/auth/caddy
                        copy_headers X-Authentik-Username X-Authentik-Groups X-Authentik-Email X-Authentik-Name X-Authentik-Uid X-Authentik-Jwt X-Authentik-Meta-Jwks X-Authentik-Meta-Outpost X-Authentik-Meta-Provider X-Authentik-Meta-App X-Authentik-Meta-Version authorization
                        trusted_proxies private_ranges
                      }
                      reverse_proxy ${target}
                    }
                  ''
                else
                  ''
                    reverse_proxy ${target}
                  '';
            };
          };
        in
        lib.listToAttrs (lib.mapAttrsToList mkVHost localServices);
    };

    my.endpoints = {
      caddy-http = {
        host = config.networking.hostName;
        port = 80;
        directAccess = {
          enable = true;
          protocol = "tcp";
          interface = "all";
        };
        monitoring.http.enable = false;
      };

      caddy-https = {
        host = config.networking.hostName;
        port = 443;
        directAccess = {
          enable = true;
          protocol = "both";
          interface = "all";
        };
        monitoring.http.enable = false;
      };
    };

    # Allow group read access to logs (for CrowdSec and Alloy)
    systemd.services.caddy.serviceConfig.UMask = "0027";

    systemd.tmpfiles.rules = [
      "d /var/log/caddy 0755 caddy caddy -"
      "z /var/log/caddy/*.log 0640 caddy caddy -"
    ];
  };
}
