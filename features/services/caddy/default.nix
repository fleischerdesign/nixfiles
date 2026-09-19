{
  config,
  lib,
  ...
}:
let
  cfg = config.my.features.services.caddy;
  # The zone decides the certificate strategy (see tlsFor below): the wildcard certificate is
  # obtained once per zone, and internal-plane names can never be covered by it.
  zone = config.my.topology.domain;
in
{
  options.my.features.services.caddy = {
    enable = lib.mkEnableOption "Caddy Web Server";

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

          # The ingress reaches every provider over the mesh overlay. A provider's LAN address
          # (10.10.10.x / 10.10.20.x / 10.10.30.x) is not routed from the edge, so proxying to it
          # dies with "dial tcp ...: i/o timeout" - the service answers 502 and the ACME challenge
          # never completes, so it never even gets a certificate. `wireguardIpv4` carries the
          # overlay address (the shim maps it to the host's WireGuard IPv4) and must win.
          overlayAddress =
            host:
            if host == null then
              null
            else if host.wireguardIpv4 != null then
              host.wireguardIpv4
            else
              host.ipv4;

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
                    address = overlayAddress (config.my.topology.hosts.${hostName} or null);
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

                  # Always overwrite (never append) the forwarded client chain. Untrusted clients
                  # must not be able to spoof X-Forwarded-* towards downstream trusted-proxy
                  # consumers such as the OpenClaw gateway, which attributes clients from these
                  # headers (openclaw trusted-proxy security checklist).
                  proxy =
                    "reverse_proxy ${target} {\n"
                    + "  header_up X-Forwarded-For {http.request.remote.host}\n"
                    + "  header_up X-Forwarded-Proto {http.request.scheme}\n"
                    + "  header_up X-Forwarded-Host {http.request.host}\n"
                    + lib.optionalString (conf.proxyOptions != "") "${conf.proxyOptions}\n"
                    + "}";

                  exemptHandlers =
                    lib.optionalString (conf.unauthenticatedPaths != [ ]) ''
                      @unauthenticatedRoute path ${lib.concatStringsSep " " conf.unauthenticatedPaths}
                      handle @unauthenticatedRoute {
                        ${proxy}
                      }
                    ''
                    + lib.optionalString conf.machineClientsBypassAuth ''
                      @nonBrowserWebsocket {
                        header Connection *Upgrade*
                        header Upgrade websocket
                        not header Origin *
                      }
                      handle @nonBrowserWebsocket {
                        ${proxy}
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

    # One certificate per zone, obtained by DNS-01 through Cloudflare, on every host that
    # terminates public names. The strategy is deliberately single: the certificate never depends
    # on where a name resolves, which is what makes split horizon and a public CA compatible.
    # Binding this certificate to the vhosts follows in a second step: an explicit `tls`
    # directive pointing at a file that does not exist yet can make Caddy reject its whole
    # configuration, so the certificate is issued before anything references it.
    sops.secrets."infra/cloudflare_api_token" = lib.mkDefault { };

    security.acme = {
      acceptTerms = true;
      defaults.email = config.my.user.email;
      certs."${zone}" = {
        domain = "*.${zone}";
        extraDomainNames = [ zone ];
        dnsProvider = "cloudflare";
        # systemd credentials rather than an environment file: lego reads the token from the path
        # the variable names, so the secret never appears in a process environment.
        credentialFiles = {
          CF_DNS_API_TOKEN_FILE = config.sops.secrets."infra/cloudflare_api_token".path;
        };
        group = "caddy";
        reloadServices = [ "caddy.service" ];
      };
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
