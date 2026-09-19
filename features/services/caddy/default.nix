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
      default =
        let
          hostName = config.networking.hostName;
          hostTopo = config.my.topology.hosts.${hostName} or null;
        in
        if hostTopo != null && hostTopo.domain != null then hostTopo.domain else config.my.topology.domain;
      description = "Base domain for exposed services (defaults to host topology domain, e.g. srv.lan.vyrx.de, edge.vyrx.de)";
    };

    authentikOutpostAddress = lib.mkOption {
      type = lib.types.str;
      # Forward-auth terminates on the central embedded outpost of the authentik
      # server, so every host's Caddy targets the same outpost.
      default = config.my.features.services.authentik.server.embeddedOutpostAddress;
      description = "Address of the Authentik outpost used for forward-auth requests.";
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

      # Generate virtualHosts from service contracts (local host only)
      virtualHosts =
        let
          localEndpoints = lib.concatLists (
            lib.mapAttrsToList (
              _svcName: contract:
              lib.filter (ep: (ep.scope == "public" || ep.scope == "internal") && ep.canonicalDomain != null) (
                lib.attrValues contract.endpoints
              )
            ) config.my.contracts.provides
          );

          # --- Ingress engine (ARCHITECTURE.md §8.1) --------------------------------
          # The declared ingress host publishes every `public` endpoint of the whole fleet,
          # not only its own, and proxies it to the provider over the LAN/overlay. That is
          # what lets jellyfin/hass/seerr/mealie be public without a public provider address.
          isIngress = config.networking.hostName == config.my.topology.ingressHost;

          overlayAddress =
            host:
            if host == null then
              null
            else if
              host.localIp != null
              && (lib.hasPrefix "10.10." host.localIp || lib.hasPrefix "192.168." host.localIp)
            then
              host.localIp
            else if host.tailscaleIp != null then
              host.tailscaleIp
            else
              host.localIp;

          flakeConfigurations =
            config._module.specialArgs.flake.nixosConfigurations or {
              "${config.networking.hostName}" = config;
            };

          remoteEndpoints =
            if !isIngress then
              [ ]
            else
              lib.concatLists (
                lib.mapAttrsToList (
                  hostName: hostConfig:
                  let
                    address = overlayAddress (config.my.features.system.networking.topology.hosts.${hostName} or null);
                  in
                  lib.optionals (hostName != config.networking.hostName && address != null) (
                    lib.concatLists (
                      lib.mapAttrsToList (
                        _svcName: contract:
                        lib.concatMap (
                          ep:
                          lib.optional (ep.scope == "public" && ep.canonicalDomain != null) {
                            inherit (ep)
                              canonicalDomain
                              extraDomains
                              port
                              auth
                              unauthenticatedPaths
                              machineClientsBypassAuth
                              customExtraConfig
                              proxyOptions
                              ;
                            target = "${address}:${toString ep.port}";
                          }
                        ) (lib.attrValues contract.endpoints)
                      ) (hostConfig.config.my.contracts.provides or { })
                    )
                  )
                ) flakeConfigurations
              );

          mkVHost = conf: {
            value = {
              extraConfig =
                let
                  target = conf.target or "127.0.0.1:${toString conf.port}";

                  proxy =
                    "reverse_proxy ${target}"
                    + lib.optionalString (conf.proxyOptions != "") " {\n${conf.proxyOptions}\n}";

                  exemptHandlers =
                    lib.optionalString (conf.unauthenticatedPaths != [ ]) ''
                      @unauthenticatedRoute path ${lib.concatStringsSep " " conf.unauthenticatedPaths}
                      handle @unauthenticatedRoute {
                        reverse_proxy ${target}
                      }
                    ''
                    + lib.optionalString conf.machineClientsBypassAuth ''
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
                if conf.customExtraConfig != null then
                  conf.customExtraConfig
                else if conf.auth == "authentik" then
                  ''
                    import authentik
                    ${exemptHandlers}
                    handle {
                      forward_auth ${cfg.authentikOutpostAddress} {
                        uri /outpost.goauthentik.io/auth/caddy
                        copy_headers X-Authentik-Username X-Authentik-Groups X-Authentik-Email X-Authentik-Name X-Authentik-Uid X-Authentik-Jwt X-Authentik-Meta-Jwks X-Authentik-Meta-Outpost X-Authentik-Meta-Provider X-Authentik-Meta-App X-Authentik-Meta-Version authorization
                        trusted_proxies private_ranges
                      }
                      ${proxy}
                    }
                  ''
                else
                  ''
                    ${proxy}
                  '';
            };
          };
        in
        # An endpoint answers on its canonical domain plus every alias it declares.
        # Wildcard aliases are skipped: dynamically minted hosts own their vhost.
        lib.listToAttrs (
          lib.concatMap (
            conf:
            map (domain: {
              name = domain;
              inherit (mkVHost conf) value;
            }) ([ conf.canonicalDomain ] ++ lib.filter (d: !lib.hasInfix "*" d) conf.extraDomains)
          ) (localEndpoints ++ remoteEndpoints)
        );
    };

    my.contracts.provides.caddy = {
      endpoints = {
        http = {
          port = 80;
          protocol = "tcp";
          scope = "public";
          directAccess = {
            enable = true;
            protocol = "tcp";
            interface = "all";
          };
          monitoring.http.enable = false;
        };

        https = {
          port = 443;
          protocol = "both";
          scope = "public";
          directAccess = {
            enable = true;
            protocol = "both";
            interface = "all";
          };
          monitoring.http.enable = false;
        };
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
