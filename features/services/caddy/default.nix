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
          # The certificate is selected by the name being served, because a wildcard certificate
          # covers exactly one label: `grafana.vyrx.de` is covered, `links.lan.vyrx.de` is not, and
          # the apex is covered by the same certificate, because
          # two challenges collide on the same `_acme-challenge` record. Everything the wildcard
          # cannot cover lives on the internal or mesh plane, which no public CA can validate, so it
          # is served by Caddy's own CA.
          coveredByWildcard =
            domain: lib.hasSuffix ".${zone}" domain && !lib.hasInfix "." (lib.removeSuffix ".${zone}" domain);
          tlsFor =
            domain:
            if coveredByWildcard domain || domain == zone then
              "tls /var/lib/acme/${zone}/fullchain.pem /var/lib/acme/${zone}/key.pem\n"
            else if
              lib.hasInfix ".lan." domain || lib.hasInfix ".mesh." domain || lib.hasInfix ".iot." domain
            then
              "tls internal\n"
            else
              "";
        in
        # An endpoint answers on its canonical domain plus every alias it declares.
        # Wildcard aliases are skipped: dynamically minted hosts own their vhost.
        lib.listToAttrs (
          lib.concatMap (
            conf:
            map (domain: {
              name = domain;
              value = (mkVHost conf).value // {
                extraConfig = tlsFor domain + (mkVHost conf).value.extraConfig;
              };
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
      defaults = {
        email = config.my.user.email;
        dnsProvider = "cloudflare";
        # lego determines the zone by asking a resolver for the SOA record. The system resolver on
        # these hosts is Tailscale MagicDNS (and Blocky on the LAN), neither of which is
        # authoritative for the public zone: asked for `vyrx.de` they answer "has no SOA record",
        # lego then walks up to the bare TLD `de.` and reports "zone could not be found" - which
        # looks exactly like a missing API permission and was misread as one. Zone discovery must
        # therefore use a public resolver, independent of the host's own DNS story.
        dnsResolver = "1.1.1.1:53";
        # lego's own propagation check asks recursive resolvers whether the challenge TXT record is
        # visible. Measured on this zone: the authoritative nameserver carried the value immediately
        # while 1.1.1.1, 8.8.8.8 and 9.9.9.9 each served a different, partly stale subset - so the
        # check can never converge, and it timed out after its full 2-minute window even with a
        # freshly cleaned zone. What it measures is CDN cache state, not the truth; the validation
        # that matters is the CA's own, and that queries the authoritative servers.
        dnsPropagationCheck = false;
        # systemd credentials rather than an environment file: lego reads the token from the path
        # the variable names, so the secret never appears in a process environment.
        credentialFiles = {
          CF_DNS_API_TOKEN_FILE = config.sops.secrets."infra/cloudflare_api_token".path;
        };
        group = "caddy";
        reloadServices = [ "caddy.service" ];
      };
      # Two orders, never one. `*.${zone}` and the apex share the same `_acme-challenge.${zone}`
      # record, so a single order puts two TXT values at that name at the same time; the CA then
      # finds a value it did not expect and rejects the authorization with
      # "Incorrect TXT record ... (and 1 more) found at _acme-challenge.<zone>" - measured here.
      # Separate orders cannot overlap: each one finishes before the next starts.
      # One order for both names. `*.${zone}` and the apex share the same `_acme-challenge.${zone}`
      # record, which is exactly why they belong in one certificate: two certificates would be
      # ordered concurrently by systemd, and each would delete the other's TXT record while it was
      # being validated - measured: the apex succeeded and the wildcard then failed with
      # "Incorrect TXT record ... (and 1 more) found at _acme-challenge.<zone>". One order presents
      # both values in a single RRset and never races a second unit.
      certs."${zone}" = {
        domain = "*.${zone}";
        extraDomainNames = [ zone ];
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
