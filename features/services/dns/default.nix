# features/services/dns/default.nix - Knot Resolver 6 with plane-correct views
#
# One resolver answers three planes, selected by the *source address* of the query and, for
# the home zone, by the door it came in through:
#
#   lan      a client on a home zone        -> the LAN address (the packet stays local)
#   overlay  a client on the mesh           -> the overlay address (reachable over wg0)
#   public   a client anywhere else         -> the ingress (services) / overlay (nodes)
#
# A name has one address per plane and the plane is a property of the question, not of the
# answer. Every record is a projection of `my.topology`, the naming contract and the endpoint
# contracts - nothing is restated.
#
# Two doors serve the same name:
#   * the home door (this resolver's own address inside a home zone, plain DNS and DoT), and
#   * the public door (the ingress, DoT only - a plain public resolver answers nobody's need).
# `dns.<domain>` resolves to the door of whoever asks: a home client reaches its own door
# over the LAN, everyone else the ingress. The views therefore also carry `dst-subnet`, so a
# foreign network that happens to use a home /24 is not treated as being at home.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.features.services.dns;
  topology = config.my.topology;

  flakeConfigurations =
    config._module.specialArgs.flake.nixosConfigurations or {
      "${config.networking.hostName}" = config;
    };

  domain = topology.domain;
  resolverName = "${cfg.subdomain}.${domain}";

  ingressHost = topology.hosts.${topology.ingressHost} or null;
  ingressAddress = if ingressHost != null then ingressHost.ipv4 else null;

  # The host that routes the home LAN is declared once (`my.topology.lanRouter`); it is the one that
  # terminates DNS-over-TLS inside it, so its own address is the home door of the resolver's name.
  deliveryHost = topology.hosts.${topology.lanRouter} or null;

  # An address is a LAN address when it is on a private home subnet. A cloud host's `ipv4`
  # is its public address and must never be handed to a LAN client.
  isLanAddress =
    address: address != null && (lib.hasPrefix "10.10." address || lib.hasPrefix "192.168." address);

  ownHost = topology.hosts.${config.networking.hostName} or null;
  ownLanAddress = if ownHost != null && isLanAddress ownHost.ipv4 then ownHost.ipv4 else null;
  ownOverlayAddress = if ownHost != null then ownHost.wireguardIpv4 else null;

  # Plain DNS is served wherever a client can reach it: inside a home zone on the LAN address, and in
  # the mesh on the overlay address. A cloud host has no LAN address and still serves the mesh - which
  # is what makes the resolver redundant for a node that is not at home, because the zones are generated
  # from the same inventory on every resolver and nothing has to be replicated at runtime.
  derivedListen =
    lib.optionalAttrs (ownLanAddress != null) { lan = ownLanAddress; }
    // lib.optionalAttrs (ownOverlayAddress != null) { overlay = ownOverlayAddress; };
  effectiveListen = cfg.listenAddresses // derivedListen;

  # DoT is served wherever the resolver already binds plain DNS - same reachability, one
  # transport added - plus this host's public door when it is the public entry. A client that
  # learned an address from us must always be able to reach it, and a client whose tunnel is
  # up reaches the overlay listener inside the tunnel even where the uplink blocks port 853.
  dotAddresses =
    if !cfg.dot then
      [ ]
    else
      lib.unique (
        lib.attrValues effectiveListen
        ++ lib.optional (ownHost != null && ownHost.ipv4 != null) ownHost.ipv4
      );

  # Knot refuses a configuration without at least one listener, so a host that has none yet
  # - the public door before DoT is switched on - runs no resolver at all.
  hasListener = effectiveListen != { } || dotAddresses != [ ];

  # A host that publishes the resolver's name, or terminates it inside a home zone.
  hasDoor = ownLanAddress != null || cfg.publicEntry;

  # Planes. The mesh subnets are the overlay; the remaining trusted zones are the LAN. The
  # guest zone is not a plane of ours: a guest client falls through to the public view.
  overlayCidrs = lib.mapAttrsToList (_: subnet: subnet.cidr) (
    lib.filterAttrs (_: subnet: subnet.trustLevel == "mesh") topology.subnets
  );
  lanCidrs = lib.mapAttrsToList (_: subnet: subnet.cidr) (
    lib.filterAttrs (
      _: subnet: subnet.trustLevel != "mesh" && subnet.trustLevel != "guest"
    ) topology.subnets
  );

  lanPlaneAddress =
    host:
    if host == null then
      null
    else if isLanAddress host.ipv4 then
      host.ipv4
    else
      host.wireguardIpv4;
  overlayAddress = host: if host == null then null else host.wireguardIpv4;

  # One rule per (name, plane). `records` (zonefile form) is used rather than `address`: an
  # `address` mapping also synthesises a reverse PTR for that address, and every public
  # endpoint resolves to the ingress, so the aggregated PTR exceeded Knot's 512 B record
  # limit and the policy loader refused to start (measured 2026-09-21). Names containing a
  # wildcard are skipped: `local-data` does not expand wildcards, and such names are minted
  # at runtime and resolve upstream.
  mkRules =
    names: addresses:
    lib.flatten (
      lib.map (
        name:
        let
          fqdn = if lib.hasSuffix "." name then name else "${name}.";
        in
        lib.optional (!(lib.hasInfix "*" name)) (
          lib.mapAttrsToList (plane: address: {
            records = "${fqdn} 60 IN A ${address}";
            tags = [ plane ];
          }) (lib.filterAttrs (_: address: address != null) addresses)
        )
      ) names
    );

  nodeRules = lib.concatLists (
    lib.mapAttrsToList (
      hostName: fqdn:
      let
        host = topology.hosts.${hostName};
      in
      mkRules [ fqdn ] {
        lan = lanPlaneAddress host;
        overlay = overlayAddress host;
        public = overlayAddress host;
      }
    ) config.my.contracts.projections.hostFqdnOf
  );

  # A device has no overlay identity, so its LAN address is the only address it has and the only one
  # the `lan` plane answers. A node that is not in the LAN reaches it over the mesh exactly when the
  # device's zone is carried there (`my.topology.announcedZones`), so the `overlay` plane answers the
  # same address for a carried zone and stays silent otherwise: a name that resolves to an address
  # nothing routes is worse than no answer at all.
  deviceRules = lib.concatLists (
    lib.mapAttrsToList (
      devName: fqdn:
      mkRules [ fqdn ] {
        lan = topology.devices.${devName}.ipv4;
        overlay =
          if builtins.elem topology.devices.${devName}.zone topology.announcedZones then
            topology.devices.${devName}.ipv4
          else
            null;
      }
    ) config.my.contracts.projections.deviceFqdnOf
  );

  # A service is named once; the plane decides which address terminates it. In the LAN plane
  # it is the serving host; in the public plane it is the ingress, the only component that
  # terminates public TLS.
  serviceRules = lib.concatLists (
    lib.mapAttrsToList (
      hostName: hostConfig:
      let
        host = topology.hosts.${hostName} or null;
      in
      lib.concatLists (
        lib.mapAttrsToList (
          _svcName: contract:
          lib.concatMap (
            ep:
            # The resolver's own name is answered by `resolverRules`, which knows which doors
            # terminate DoT; here it would get the serving host's overlay address instead -
            # an address where no DoT listener exists (measured 2026-09-21).
            mkRules
              (lib.filter (n: n != resolverName) (
                lib.optionals (ep.canonicalDomain != null) [ ep.canonicalDomain ] ++ ep.extraDomains
              ))
              {
                lan = lanPlaneAddress host;
                overlay = overlayAddress host;
                public = if ep.scope == "public" then ingressAddress else null;
              }
          ) (lib.attrValues contract.endpoints)
        ) (hostConfig.config.my.contracts.provides or { })
      )
    ) flakeConfigurations
  );

  # The resolver's own name answers with a door that terminates DoT. Inside a home zone that
  # is the delivery point's LAN address; from the mesh it is the resolver's overlay address,
  # so the lookup and the query both stay inside the tunnel (which also keeps it working on
  # uplinks that block port 853); everyone else gets the ingress.
  resolverRules = mkRules [ resolverName ] {
    lan = if deliveryHost == null then null else deliveryHost.ipv4;
    overlay = if deliveryHost == null then null else deliveryHost.wireguardIpv4;
    public = ingressAddress;
  };

  blocklistDir = "/var/lib/knot-resolver";
  blocklistRpz = "${blocklistDir}/blocklist.rpz";
  blocklistEntries = map (url: {
    inherit url;
    host = lib.head (
      lib.splitString "/" (lib.removePrefix "https://" (lib.removePrefix "http://" url))
    );
  }) cfg.blocklists;
in
{
  options.my.features.services.dns = {
    enable = lib.mkEnableOption "Knot Resolver 6 as the fleet resolver (plane-correct views)";

    # What the resolver will answer, as a projection: one entry per (name, plane). It exists so a check
    # can state an invariant about the answers instead of recomputing the derivation - and the
    # invariant that matters is the one learnt the hard way: a name must never resolve to an address
    # nothing routes, which is why a device in a zone the mesh does not carry is not answered off the
    # LAN at all.
    answers = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Name as the resolver stores it, with the trailing dot of a zone file";
            };
            plane = lib.mkOption {
              type = lib.types.str;
              description = "Plane the answer belongs to: lan, overlay or public";
            };
            address = lib.mkOption {
              type = lib.types.str;
              description = "The address the resolver answers in that plane";
            };
          };
        }
      );
      readOnly = true;
      description = "The A records the resolver answers, projected from the rules it is built from";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 53;
      description = ''
        TCP/UDP port for plain DNS. Staging runs the resolver on a different port so the
        generated configuration can be proven against real names before the live resolver
        is replaced.
      '';
    };

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "dns";
      description = "Subdomain below the zone that names this resolver, e.g. `dns` -> dns.<domain>.";
    };

    dot = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Serve DNS-over-TLS on this host's own address, using the certificate for the
        resolver's name. A phone's private DNS setting speaks DoT and nothing else, so this
        is what lets a client keep using our resolver away from home without the tunnel
        having to carry a home prefix.
      '';
    };

    dotPort = lib.mkOption {
      type = lib.types.port;
      default = 853;
      description = "TCP port for DNS-over-TLS.";
    };

    publicEntry = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        This host is the public door: it declares the resolver's name as a public endpoint,
        which projects the DNS record and the firewall rule. Exactly one host may do so -
        the naming invariant allows one owner per name.
      '';
    };

    rateLimit = lib.mkOption {
      type = lib.types.ints.positive;
      default = 200;
      description = ''
        Per-client rate limit for the public door. DoT runs over TCP, so it is not an
        amplification vector; the limit is a floor against a runaway client, not the
        primary defence.
      '';
    };

    listenAddresses = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        lan = "10.10.10.10";
        overlay = "10.10.100.10";
      };
      description = "Overrides for the derived plain-DNS listeners; the default reads the host's own inventory entry.";
    };

    blocklists = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts" ];
      description = ''
        Hosts-format blocklists, fetched on a timer and converted to an RPZ zone in the
        resolver's state directory; a blocked name answers NXDOMAIN.
      '';
    };

    blocklistRefresh = lib.mkOption {
      type = lib.types.str;
      default = "daily";
      description = "systemd calendar expression for the blocklist refresh timer.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !cfg.dot || (ownHost != null && ownHost.ipv4 != null);
        message = "DNS: DoT needs an address to serve on, and this host declares none in the topology.";
      }
    ];

    # The projection of the same rules the resolver is built from, in the shape a check wants it:
    # `{ name, plane, address }` per record. A rule reads `"<fqdn> 60 IN A <address>"`, so the name is
    # its first field and the address its last.
    my.features.services.dns.answers = lib.unique (
      lib.map (
        rule:
        let
          parts = lib.splitString " " rule.records;
        in
        {
          name = builtins.head parts;
          plane = builtins.head rule.tags;
          address = lib.last parts;
        }
      ) (nodeRules ++ deviceRules ++ serviceRules ++ resolverRules)
    );

    # The hosts resolve through `my.topology.resolvers` (the resolver's own zone address),
    # not through 127.0.0.1: the resolver binds the zone addresses, so pointing resolv.conf
    # at localhost would ask an address nothing listens on.
    networking.resolvconf.useLocalResolver = lib.mkForce false;

    services.knot-resolver = {
      enable = hasListener;
      settings = {
        network = {
          listen =
            lib.mapAttrsToList (_: address: {
              interface = address;
              port = cfg.port;
              kind = "dns";
            }) effectiveListen
            ++ map (address: {
              interface = address;
              port = cfg.dotPort;
              kind = "dot";
            }) dotAddresses;
        }
        // lib.optionalAttrs cfg.dot {
          tls = {
            cert-file = "/var/lib/acme/${resolverName}/fullchain.pem";
            key-file = "/var/lib/acme/${resolverName}/key.pem";
          };
        };

        views = [
          (
            {
              subnets = lanCidrs;
              tags = [ "lan" ];
            }
            // lib.optionalAttrs (ownLanAddress != null) {
              dst-subnet = ownLanAddress;
            }
          )
          {
            subnets = overlayCidrs;
            tags = [ "overlay" ];
          }
          {
            # Fallback: everything that is neither on a home zone nor on the mesh. It must
            # exist and be last, because a client matching no view carries no tags and
            # would then see no local records at all.
            subnets = [
              "0.0.0.0/0"
              "::/0"
            ];
            tags = [ "public" ];
          }
        ];

        local-data = {
          rules = nodeRules ++ deviceRules ++ serviceRules ++ resolverRules;
          rpz = lib.optionals (cfg.blocklists != [ ]) [
            {
              file = blocklistRpz;
              watchdog = true;
            }
          ];
        };
      }
      // lib.optionalAttrs cfg.publicEntry {
        rate-limiting = {
          enable = true;
          rate-limit = cfg.rateLimit;
        };
      };
    };

    # A resolver opens what it serves: the plain port wherever it binds a plain listener, and the DoT
    # port where it terminates TLS. Measured on the cloud resolver: it served the mesh on 10.10.100.1
    # and its firewall dropped every query that arrived there, because only the DoT port was opened.
    networking.firewall = {
      allowedTCPPorts =
        lib.optional cfg.dot cfg.dotPort ++ lib.optional (effectiveListen != { }) cfg.port;
      allowedUDPPorts = lib.optional (effectiveListen != { }) cfg.port;
    };

    # Knot reads the certificate itself and its watchdog reloads it when it changes, so the
    # certificate is issued where the name terminates - exactly as every other name here.
    # It is declared as soon as the host has a door, *not* when it starts serving DoT: the
    # resolver refuses to start if the file is missing, so the certificate has to exist
    # first (the rollout enables DoT in a second step for the same reason).
    security.acme.certs = lib.optionalAttrs hasDoor {
      ${resolverName} = {
        domain = resolverName;
        group = "knot-resolver";
      };
    };

    # The order resolves the ACME API host itself, so it must not depend on whatever owns
    # /etc/resolv.conf: it gets the resolver from the inventory, the same one every other
    # lookup here uses. (Before the static module handed its resolvers to openresolv, this
    # host's file was a stale DHCP lease and the order timed out, leaving only the
    # self-signed placeholder - measured 2026-09-21.)
    systemd.services."acme-order-renew-${resolverName}" = lib.mkIf hasDoor {
      serviceConfig.BindReadOnlyPaths = [
        "${
          pkgs.writeText "acme-resolv.conf" (lib.concatMapStrings (r: "nameserver ${r}\n") topology.resolvers)
        }:/etc/resolv.conf"
      ];
    };

    # The certificate is issued for the resolver's group, and that group belongs to the
    # resolver service - which a host may not run yet, because the public door declares the
    # name and the certificate before DoT is switched on. Declared here, next to the
    # certificate that needs it.
    users.groups.knot-resolver = lib.mkIf hasDoor { };

    # The manager chdirs into its runtime directory. If systemd removes that directory while
    # the service is restarted or reloaded, the manager's working directory disappears and it
    # aborts with a FileNotFoundError (measured 2026-09-21).
    systemd.services.knot-resolver.serviceConfig.RuntimeDirectoryPreserve = "yes";

    systemd.services.knot-resolver.after = lib.optional (
      cfg.dot && hasListener
    ) "acme-${resolverName}.service";

    # The RPZ file must exist before the resolver starts; an empty one is a valid, empty
    # policy (measured).
    systemd.tmpfiles.rules = lib.optionals (cfg.blocklists != [ ] && hasListener) [
      "d ${blocklistDir} 0770 knot-resolver knot-resolver -"
      "f ${blocklistRpz} 0644 knot-resolver knot-resolver -"
    ];

    systemd.services.knot-blocklist = lib.mkIf (cfg.blocklists != [ ] && hasListener) {
      description = "Refresh the resolver's blocklist (hosts -> RPZ) and reload it";
      after = [
        "network-online.target"
        "knot-resolver.service"
      ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        StateDirectory = "knot-resolver";
        RuntimeDirectory = "knot-resolver";
      };
      # The list's host is resolved through this host's own resolution path: the resolver module makes
      # every host resolve through our doors, so there is one place that decides how a name is looked
      # up and no second resolver list to keep in step. `--resolve` pins the address for the transfer.
      script = ''
        set -eu
        raw="$(mktemp)"
        : > "$raw"
        ${lib.concatMapStrings ({ url, host }: ''
          ip="$(${pkgs.bind.dnsutils}/bin/dig +short +time=5 +tries=1 '${host}' A | ${pkgs.gnugrep}/bin/grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)"
          ${pkgs.curl}/bin/curl --fail --silent --show-error --location --resolve "${host}:443:$ip" '${url}' >> "$raw"
        '') blocklistEntries}
        # /etc/hosts -> RPZ. Inline comments are stripped first: entries often carry the URL
        # they came from, and those words would otherwise become owners (measured: a zone
        # parse error "owner is invalid" on '#.' and a Wikipedia URL).
        ${pkgs.gawk}/bin/awk '
          { sub(/#.*/, "") }
          NF >= 2 {
            for (i = 2; i <= NF; i++) {
              d = tolower($i)
              if (d ~ /^[0-9.]+$/) continue
              if (d ~ /^(localhost|local|broadcasthost|broadcast|ip6-)/) continue
              if (d !~ /^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$/) continue
              print d ". 60 IN CNAME ."
            }
          }
        ' "$raw" | ${pkgs.coreutils}/bin/sort -u > "${blocklistRpz}.new"
        # Never install a file the resolver cannot parse: an invalid RPZ makes the policy
        # loader abort, and a resolver that refuses to start is worse than a stale list.
        if ${pkgs.gnugrep}/bin/grep -qvE '^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+\.[[:space:]]+60[[:space:]]+IN[[:space:]]+CNAME[[:space:]]+\.$' "${blocklistRpz}.new"; then
          echo "blocklist: refusing to install a malformed RPZ" >&2
          rm -f "$raw" "${blocklistRpz}.new"
          exit 1
        fi
        install -o knot-resolver -g knot-resolver -m 0644 "${blocklistRpz}.new" "${blocklistRpz}"
        rm -f "$raw" "${blocklistRpz}.new"
        # No reload here: the RPZ is watched (`watchdog: true`), so the running resolver picks
        # the new file up itself. `kresctl reload` is not safe for this service - the manager
        # chdirs into its runtime directory, and a reload removes that directory under it.
      '';
    };

    systemd.timers.knot-blocklist = lib.mkIf (cfg.blocklists != [ ] && hasListener) {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.blocklistRefresh;
        # A fresh host has no blocklist yet, and waiting up to a day for the first one would
        # leave it unblocked for exactly that long.
        OnStartupSec = "2min";
        Persistent = true;
      };
    };

    my.contracts.provides.dns = {
      endpoints = {
        dns = {
          port = cfg.port;
          protocol = "both";
          scope = "internal";
          directAccess = {
            enable = true;
            protocol = "both";
            interface = "all";
          };
          monitoring.http.enable = false;
        };
      }
      // lib.optionalAttrs cfg.publicEntry {
        # The public door: one name, one owner. `ingress = false` because no HTTP vhost
        # terminates it - the resolver does - while the name is still projected into
        # public DNS and its port into the firewall.
        ${cfg.subdomain} = {
          inherit (cfg) subdomain;
          port = cfg.dotPort;
          protocol = "tcp";
          scope = "public";
          ingress = false;
          publicExempt = "DNS has no authentication layer; it is an open resolver by design.";
          monitoring.http.enable = false;
        };
      };
    };
  };
}
