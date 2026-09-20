{
  config,
  lib,
  ...
}:
let
  cfg = config.my.features.services.caddy;
  zone = config.my.topology.domain;
  # The criterion for "can we get a certificate for this name" is not the scope but whether the name
  # lies inside the zone this API manages: only then can `_acme-challenge.<name>` be published, and
  # DNS-01 does not care where the name resolves. Internal-plane names are subdomains of the public
  # zone, so they qualify too - which is what makes a vhost never need Caddy's own CA.
  inZone = domain: domain == zone || lib.hasSuffix ".${zone}" domain;

  # Every public name this host terminates - its own endpoints, plus every host's when it runs the
  # ingress - computed once and used both for the certificate declarations and for the `tls`
  # bindings, so the two cannot drift apart.
  #
  # No wildcard and no apex: Cloudflare's own Universal SSL certificate for this zone is validated by
  # TXT records at `_acme-challenge.<zone>`, managed internally and invisible to the zone API
  # (measured: DNS serves them, the API does not know them). No third party can prove control of
  # that name, so `*.${zone}` and `${zone}` cannot be issued by us - while per-name challenges are
  # free and publish correctly (measured: `_acme-challenge.<name>.<zone>` appears in the zone within
  # three seconds of lego presenting it).
  flakeConfigurations =
    config._module.specialArgs.flake.nixosConfigurations or {
      "${config.networking.hostName}" = config;
    };
  isIngress = config.networking.hostName == config.my.topology.ingressHost;
  overlayAddress =
    host:
    if host == null then
      null
    else if host.wireguardIpv4 != null then
      host.wireguardIpv4
    else
      host.ipv4;
  terminatedEndpoints =
    lib.concatMap (
      contract: lib.filter (ep: ep.canonicalDomain != null) (lib.attrValues contract.endpoints)
    ) (lib.attrValues (config.my.contracts.provides or { }))
    ++ lib.optionals isIngress (
      lib.concatLists (
        lib.mapAttrsToList (
          hostName: hostConfig:
          lib.optionals (hostName != config.networking.hostName) (
            lib.concatMap (
              contract: lib.filter (ep: ep.canonicalDomain != null) (lib.attrValues contract.endpoints)
            ) (lib.attrValues (hostConfig.config.my.contracts.provides or { }))
          )
        ) flakeConfigurations
      )
    );
  publicNames = lib.unique (
    lib.filter inZone (
      map (ep: ep.canonicalDomain) terminatedEndpoints
      ++ lib.concatMap (
        ep:
        # Aliases count as well, and internal-plane aliases such as `docs.lan.<zone>` are ordinary
        # subdomains of the public zone. Wildcards are skipped: their vhosts are minted at runtime
        # and Caddy issues those on demand.
        lib.filter (d: d != null && !lib.hasInfix "*" d) ep.extraDomains
      ) terminatedEndpoints
    )
  );
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
          # The certificate is chosen by the name being served: every public name this host
          # terminates has its own certificate issued here, and internal-plane names - which no
          # public CA can validate - are served by Caddy's own CA.
          tlsFor =
            domain:
            if isIngress then
              # The ingress is where public names resolve, so Caddy's automatic HTTPS (HTTP-01)
              # already works there and is the right challenge for it. Only a host that cannot be
              # reached for validation - because split horizon sends the name elsewhere - needs a
              # certificate obtained by DNS-01 instead. Each terminator uses the challenge it can
              # satisfy; none of them copies key material from another.
              ""
            else if lib.elem domain publicNames then
              "tls /var/lib/acme/${domain}/fullchain.pem /var/lib/acme/${domain}/key.pem\n"
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

    # One certificate per public name, obtained by DNS-01 through Cloudflare, on the host that
    # serves it. The strategy is deliberately single: the certificate never depends on where a name
    # resolves, which is what makes split horizon and a public CA compatible. `certs` below and the
    # `tls` bindings in the vhosts are both derived from one computed name list, so they cannot
    # drift apart, and the ACME unit is retried by its own timer when a resolver's cache defeats an
    # attempt.
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
        # lego's own propagation check waits until the challenge record is actually visible before
        # asking the CA to validate. It must stay on: with it disabled the CA is asked within a
        # second of the API write, sees NXDOMAIN because the record has not propagated yet, and that
        # NXDOMAIN is then cached negatively for the zone's whole SOA minimum (1800 s here) - which
        # makes every retry for the next half hour fail. Measured: with the check off, all four
        # orders on hom-srv-01 failed with exactly that NXDOMAIN. It is pinned to a public resolver
        # for the same reason the zone lookup is: these hosts resolve through Tailscale MagicDNS.
        dnsPropagationCheck = true;
        # systemd credentials rather than an environment file: lego reads the token from the path
        # the variable names, so the secret never appears in a process environment.
        credentialFiles = {
          CF_DNS_API_TOKEN_FILE = config.sops.secrets."infra/cloudflare_api_token".path;
        };
        group = "caddy";
        reloadServices = [ "caddy.service" ];
      };
      # One certificate per public name, issued where it is used: no key material is copied between
      # hosts, each host rotates its own, and a compromise stays local (the model SPIRE, Vault PKI
      # and cert-manager follow - one policy, per-consumer credentials). The apex and wildcards are
      # absent because Cloudflare's own Universal SSL owns `_acme-challenge.${zone}`.
      # The ingress declares none: its names resolve to it, so Caddy's automatic HTTPS already
      # obtains and renews them there, and declaring them again would issue a second, redundant set.
      # Every other host declares one certificate per public name it terminates.
      certs = lib.mkIf (!isIngress) (
        lib.genAttrs publicNames (name: {
          domain = name;
        })
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

    # A configuration change restarts Caddy instead of reloading it.
    #
    # Measured twice on 2026-09-20: the in-process reload ended in "Reload operation timed out.
    # Killing reload process." and left the service listening but answering nothing for any vhost -
    # from the LAN and through the ingress alike - while an isolated reproduction of every mechanism
    # we could think of (unreadable, truncated and mismatched certificate files; files rewritten
    # during the load; in-flight requests with default and finite grace periods; five concurrent
    # reloads; fourteen concurrent forced reloads on an unchanged config with fourteen bound sites)
    # failed to hang even once. What the production log does show is the load stalling in Caddy's own
    # admin-endpoint teardown (`stopping current admin endpoint` -> `10s timeout`), and a reload
    # necessarily round-trips through that endpoint while a restart never does. The root cause is not
    # proven; the affected code path is simply not used any more. See QUALITY.md 5.0.
    #
    # This is the module's documented knob for exactly this trade-off (`enableReload`), not an
    # override of `ExecReload`: `lib.mkForce` on that list does not displace the module's command,
    # which survives in the rendered unit - also measured.
    services.caddy.enableReload = false;

    systemd.tmpfiles.rules = [
      "d /var/log/caddy 0755 caddy caddy -"
      "z /var/log/caddy/*.log 0640 caddy caddy -"
    ];
  };
}
