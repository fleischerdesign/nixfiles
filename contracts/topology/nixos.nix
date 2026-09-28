# contracts/topology/nixos.nix
# Topology schema, derived policy and inventory validation. The site facts themselves live in
# inventory/ (subnets, hosts, devices) and are composed explicitly by lib/mk-system.nix; this
# module owns the shape of those facts, what is derived from them, and what rejects a bad one.
{
  config,
  lib,
  cidrLib,
  ...
}:

let
  cfg = config.my.topology;

  # The trust levels of the lattice, in one place: they are the vocabulary every policy in this
  # repository is written in - an endpoint's `from`, a device's reachability, the source map below -
  # so the list must not exist more than once. A level is not a zone: zones are addressed, levels are
  # judged, and the mapping between them is a fact of the inventory (`subnets.<zone>.trustLevel`).
  trustLevelNames = [
    "infra"
    "corp"
    "mesh"
    "iot"
    "guest"
  ];
  trustLevel = lib.types.enum trustLevelNames;

  # Submodule for individual subnet definition
  subnetSubmodule = lib.types.submodule {
    options = {
      cidr = lib.mkOption {
        type = lib.types.str;
        description = "Network CIDR block (e.g. 10.10.10.0/24)";
      };
      gateway = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "10.10.20.1";
        description = ''
          Address of the router *inside* this subnet. It has to live in the zone: a gateway in a
          different subnet cannot be used as a default route at all (the kernel rejects it with
          "Nexthop has invalid gateway") and DHCP clients would learn a router they cannot reach.
        '';
      };
      gatewayHost = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Inventory host that owns this subnet's gateway address, when managed by the fleet.";
      };
      trustLevel = lib.mkOption {
        type = trustLevel;
        description = "Trust category of this subnet: a policy label, not a rank. Nothing enforces lattice order between levels and nothing reads their position in the list.";
      };
      description = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Human-readable description of subnet purpose";
      };
    };
  };

  # Submodule for host registry entry
  hostSubmodule = lib.types.submodule {
    options = {
      # A zone is a subnet name, not a trust level: the reference is validated against the
      # declared subnets below, so an unknown zone fails the build instead of silently becoming
      # its own trust level somewhere downstream.
      zone = lib.mkOption {
        type = lib.types.str;
        description = "Subnet of the inventory this host lives in (a my.topology.subnets key)";
      };
      ipv4 = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Primary physical / WAN IPv4 address";
      };
      gateway = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Default gateway IPv4 address";
      };

      interface = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "enp2s0";
        description = ''
          Primary network interface of the host. Single source of truth for every module that
          has to address, bind or trust an interface (static addressing, gateway, ssh).
        '';
      };

      wireguardIpv4 = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Static WireGuard mesh overlay IPv4 (10.10.100.x)";
      };
      wireguardIpv6 = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Static WireGuard mesh overlay RFC 4193 ULA IPv6 (fd10:1000:100::x)";
      };
      wireguardPublicKey = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "WireGuard Ed25519 public key for mesh peering";
      };
      wireguardRelay = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether this host acts as a public WireGuard mesh relay hub";
      };
      hostType = lib.mkOption {
        type = lib.types.enum [
          "server"
          "workstation"
          "client"
          "embedded"
        ];
        default = "server";
        description = "Classification of the node";
      };
      mac = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Physical MAC address for static DHCP binding";
      };

      # Apps that a rendered client must keep *outside* the tunnel. It is a per-device fact, not a
      # fleet-wide one: the key exists only in the Android implementation of the client (verified in
      # `com.wireguard.config.Interface`: `ExcludedApplications` in `[Interface]`, package names,
      # comma-separated, and mutually exclusive with `IncludedApplications`), so an iOS client would
      # refuse the file rather than ignore the line. Measured: Android binds an application to the VPN
      # network, and a VPN network without `INTERNET` is not used by apps that require that capability -
      # which is how Google's push transport ends up without a network to rebuild its connection on.
      # Excluding it is therefore not about routes (its destinations are outside `AllowedIPs` anyway),
      # but about which network the app is bound to.
      excludedApplications = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Package names a rendered client must keep outside the tunnel (Android clients)";
      };
    };
  };

  # Submodule for IoT/microcontroller device definition
  deviceSubmodule = lib.types.submodule {
    options = {
      # Like a host's zone: a subnet name, validated against the inventory.
      zone = lib.mkOption {
        type = lib.types.str;
        default = "iot";
        description = "Subnet of the inventory this device lives in (a my.topology.subnets key)";
      };
      ipv4 = lib.mkOption {
        type = lib.types.str;
        description = "Static IPv4 address allocated to the device";
      };
      mac = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Physical MAC address for static DHCP reservation";
      };
      platform = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.enum [
            "esp32"
            "esp8266"
            "rp2040"
          ]
        );
        default = null;
        description = ''
          Microcontroller platform architecture. Null for devices that are not microcontrollers
          (printers, access points, media hardware); ESPHome requires it for the devices it manages.
        '';
      };
      board = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Hardware board definition target, for devices flashed from source";
      };
      description = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Human-readable description of device function";
      };

      # What this device offers to the fleet, and who may use it over the mesh. A device has no
      # configuration of its own - this *is* its firewall, projected onto the host that routes its
      # zone - so a port that is not declared here is a port no mesh member reaches. `from` is required
      # and cannot be empty: a declaration without a source would be a port nobody may use, which is a
      # hole in the inventory rather than in the network.
      endpoints = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              port = lib.mkOption {
                type = lib.types.port;
                description = "Port the device serves on its one address";
              };
              protocol = lib.mkOption {
                type = lib.types.enum [
                  "tcp"
                  "udp"
                  "both"
                ];
                default = "tcp";
                description = "Transport protocol of that port";
              };
              from = lib.mkOption {
                type = lib.types.nonEmptyListOf trustLevel;
                description = ''
                  Trust levels whose members may reach this port over the mesh. Written in levels, not
                  in addresses, because the same device is asked from a phone on the mesh and, once the
                  segment is split, from another zone - and the answer must not depend on the path.
                '';
              };
              description = lib.mkOption {
                type = lib.types.str;
                default = "";
                description = "Why this port is reachable from outside the device's own zone";
              };
            };
          }
        );
        default = { };
        description = "Ports this device offers, and the trust levels that may reach them over the mesh";
      };
    };
  };
in
{
  options.my.topology = {
    domain = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Primary root domain for all cluster services and DNS zones";
    };

    # Single source of truth for the public ingress host. The Caddy ingress engine and the
    # Cloudflare DNS projection both read this, so ingress responsibility is declared once
    # (docs/architecture.md §7.1).
    ingressHost = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Topology host that terminates public ingress traffic.";
    };

    # The host that routes the home LAN, declared the way the ingress host is. It is the next hop for
    # a node that reaches a home zone from outside, the home door of the resolver, and the host that
    # has to allow forwarding into those zones. Which zones it carries follows from the inventory
    # (`announcedZones`), so no zone list is maintained next to this declaration.
    lanRouter = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Topology host that routes the home LAN.";
    };

    upstreamRouter = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Inventory host representing the upstream router managed by the router adapter.";
    };

    accessPoint = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Inventory host representing the managed access point.";
    };

    primaryWireguardHub = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Primary relay used for the overlay's aggregate routes.";
    };

    ntpZones = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Zones whose clients may use the site's NTP service.";
    };

    defaultDhcpZone = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Subnet offered to DHCP clients without an inventory reservation.";
    };

    # The hosts that serve DNS. They generate the same zones from this inventory, so a name has one
    # answer wherever it is asked, and nothing has to be replicated between them at runtime. Each one is
    # a door for the mesh: a node that is not fixed at home can ask any of them, which is what removes
    # the single point of failure - and a host that is declared here but does not run the resolver is a
    # build failure, not a surprise during an outage.
    resolverHosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "Topology hosts that serve DNS (the home door and the mesh doors)";
    };

    resolvers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ config.my.topology.hosts.${config.my.topology.lanRouter}.ipv4 ];
      description = ''
        The resolvers handed to hosts and DHCP clients, starting with the home door of the resolver on
        the host that routes the home LAN. The uplink router is deliberately not in this list: it knows
        none of our names, so a client that fell back to it would resolve the public internet and fail
        silently on everything internal. A client resolves through our doors or not at all.
      '';
    };

    # The lattice's vocabulary as data, so a policy can be written in levels without repeating the
    # list: the enums in this file, an endpoint's `from`, a device's reachability all read it.
    # Listed most-trusted-first for humans; no mechanism reads the order, only membership.
    trustLevels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      description = "The trust levels of the lattice, most trusted first";
    };

    subnets = lib.mkOption {
      type = lib.types.attrsOf subnetSubmodule;
      default = { };
      description = "Declared network segments and VLANs";
    };

    hosts = lib.mkOption {
      type = lib.types.attrsOf hostSubmodule;
      default = { };
      description = "Full inventory of cluster nodes and infrastructure devices";
    };

    devices = lib.mkOption {
      type = lib.types.attrsOf deviceSubmodule;
      default = { };
      description = "Inventory of IoT microcontrollers and peripheral smart home hardware";
    };

    wifi = {
      ssid = lib.mkOption {
        type = lib.types.str;
        description = ''
          Fleet-wide WLAN name. The single source of truth: the access point radiates it and the
          microcontrollers store it, so the two cannot drift apart.
        '';
      };
    };

    trustedSubnets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Subnets with elevated trust level, synthesized for firewall and IPS whitelisting";
    };

    # The home zones the mesh carries. Not declared but derived, because the reason to carry a zone is
    # a fact about the inventory: a zone is carried when it holds a device that has no overlay
    # identity of its own. Such a device - a printer, a relay, a microcontroller - has one address and
    # no second one, so a node outside the LAN reaches it only when its zone is routed there. A host
    # zone is never carried: its hosts have an overlay address, and carrying the zone would put every
    # device behind it within reach of every mesh node. The guest zone is never carried: it is not
    # ours. A host decides whether it sits inside a zone by its own zone membership, which is why the
    # carried zones - not their /24 arithmetic - are what the wireguard and DNS modules read.
    announcedZones = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      description = "Home zones carried into the mesh: those holding a device without an overlay identity";
    };

    # The zones that make up the home LAN: every subnet that is neither the overlay nor the guest
    # zone. Derived, so the modules that have to tell "at home" from "away" (`wireguard`,
    # `resolver`) read one rule instead of naming zones - the rule is the trust level, not a list.
    lanZones = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      description = "Zones that make up the home LAN: every subnet that is neither the mesh nor guest";
    };

    # Which addresses carry which trust level, derived from the inventory. Both addresses of every host
    # are in here - the one it holds inside its zone and the one it holds on the mesh - because a
    # question about trust is a question about *who is asking*, and the answer must not change with the
    # path: the same phone on the home WLAN and on the mesh is the same trust level. Devices are not
    # sources: their traffic reaches another zone through the uplink router, never through ours.
    sourcesByTrust = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      readOnly = true;
      description = "Trust level -> the addresses whose traffic is judged at that level";
    };
  };

  # Consumers read my.topology directly; no parallel compatibility namespace is maintained.
  config =
    let
      subnetNames = builtins.attrNames cfg.subnets;
      siteHostReferences = lib.filter (name: name != null) (
        lib.unique [
          cfg.ingressHost
          cfg.lanRouter
          cfg.upstreamRouter
          cfg.accessPoint
          cfg.primaryWireguardHub
        ]
      );
      missingSiteHosts = lib.filter (name: !(cfg.hosts ? ${name})) siteHostReferences;
      missingRequiredSiteRoles =
        if (cfg.domain or null) == null then
          [ ]
        else
          lib.filter (name: name == null) [
            cfg.ingressHost
            cfg.lanRouter
            cfg.upstreamRouter
            cfg.accessPoint
            cfg.primaryWireguardHub
          ];
      invalidPrimaryHub =
        let
          host =
            if cfg.primaryWireguardHub == null then null else cfg.hosts.${cfg.primaryWireguardHub} or null;
        in
        cfg.primaryWireguardHub != null && (host == null || !host.wireguardRelay);
      invalidNtpZones = lib.filter (zone: !(cfg.subnets ? ${zone})) cfg.ntpZones;
      invalidDefaultDhcpZone = cfg.defaultDhcpZone != null && !(cfg.subnets ? ${cfg.defaultDhcpZone});
      invalidGatewayHosts = lib.filterAttrs (
        _: subnet: subnet.gatewayHost != null && !(cfg.hosts ? ${subnet.gatewayHost})
      ) cfg.subnets;
      invalidUpstreamRouter =
        let
          host = if cfg.upstreamRouter == null then null else cfg.hosts.${cfg.upstreamRouter} or null;
        in
        host != null && host.ipv4 == null;
      hostsWithBadZone = lib.attrNames (
        lib.filterAttrs (_: host: !(builtins.elem host.zone subnetNames)) cfg.hosts
      );
      devicesWithBadZone = lib.attrNames (
        lib.filterAttrs (_: device: !(builtins.elem device.zone subnetNames)) cfg.devices
      );

      # Every IPv4 fact in the inventory, tagged for the message. A cloud host's public address
      # and a provider gateway are addresses too: syntax and uniqueness apply to all of them,
      # while subnet membership is only asserted where the zone is an addressing container
      # (devices, overlay addresses, subnet gateways) - a cloud host's public address lives
      # outside its mesh zone by design, and a provider gateway lives outside every zone.
      v4Facts =
        lib.concatLists (
          lib.mapAttrsToList (
            name: host:
            lib.optional (host.ipv4 != null) {
              inherit name;
              value = host.ipv4;
              kind = "host ipv4";
            }
            ++ lib.optional (host.gateway != null) {
              inherit name;
              value = host.gateway;
              kind = "host gateway";
            }
            ++ lib.optional (host.wireguardIpv4 != null) {
              inherit name;
              value = host.wireguardIpv4;
              kind = "host overlay address";
            }
          ) cfg.hosts
        )
        ++ lib.concatLists (
          lib.mapAttrsToList (name: device: [
            {
              inherit name;
              value = device.ipv4;
              kind = "device ipv4";
            }
          ]) cfg.devices
        )
        ++ lib.concatLists (
          lib.mapAttrsToList (
            name: subnet:
            lib.optional (subnet.gateway != null) {
              inherit name;
              value = subnet.gateway;
              kind = "subnet gateway";
            }
          ) cfg.subnets
        );
      malformedV4 = lib.filter (fact: !cidrLib.validV4 fact.value) v4Facts;

      v6Facts = lib.concatLists (
        lib.mapAttrsToList (
          name: host:
          lib.optional (host.wireguardIpv6 != null) {
            inherit name;
            value = host.wireguardIpv6;
          }
        ) cfg.hosts
      );
      malformedV6 = lib.filter (fact: !cidrLib.validV6 fact.value) v6Facts;
      canonicalV6Addresses = map (fact: cidrLib.canonicalV6 fact.value) (
        lib.filter (fact: cidrLib.validV6 fact.value) v6Facts
      );
      duplicateV6 = lib.unique (
        lib.filter (
          address: builtins.length (lib.filter (other: other == address) canonicalV6Addresses) > 1
        ) canonicalV6Addresses
      );

      # Uniqueness covers addresses assigned to inventory nodes: host and device addresses
      # and overlay addresses. Subnet gateways name router interfaces by design (hom-rt-01's
      # own address IS the infra gateway) and host gateways are provider routers outside every
      # zone, so neither class participates here - but a node address colliding with either
      # would still collide with the node holding it, which is what this checks.
      assignedV4Facts =
        lib.concatLists (
          lib.mapAttrsToList (
            name: host:
            lib.optional (host.ipv4 != null) {
              inherit name;
              value = host.ipv4;
              kind = "host ipv4";
            }
            ++ lib.optional (host.wireguardIpv4 != null) {
              inherit name;
              value = host.wireguardIpv4;
              kind = "host overlay";
            }
          ) cfg.hosts
        )
        ++ lib.mapAttrsToList (name: device: {
          inherit name;
          value = device.ipv4;
          kind = "device ipv4";
        }) cfg.devices;
      assignedV4 = map (fact: fact.value) assignedV4Facts;
      duplicateV4 = lib.unique (
        lib.filter (
          address: builtins.length (lib.filter (other: other == address) assignedV4) > 1
        ) assignedV4
      );
      gatewayConflicts = lib.concatLists (
        lib.mapAttrsToList (
          zone: subnet:
          lib.concatMap (
            fact:
            lib.optional (
              fact.value == subnet.gateway && fact.name != subnet.gatewayHost
            ) "${zone} gateway ${subnet.gateway} conflicts with ${fact.name}"
          ) assignedV4Facts
        ) cfg.subnets
      );

      malformedCidrs = lib.filter (cidrText: cidrLib.prefixLength cidrText == null) (
        lib.mapAttrsToList (_: subnet: subnet.cidr) cfg.subnets
      );

      subnetPairs = lib.concatLists (
        lib.imap0 (
          index: left:
          map (right: {
            inherit left right;
          }) (lib.drop (index + 1) subnetNames)
        ) subnetNames
      );
      overlappingSubnets = lib.filter (
        pair: cidrLib.overlaps cfg.subnets.${pair.left}.cidr cfg.subnets.${pair.right}.cidr
      ) subnetPairs;

      # Membership is checked only against IPv4 subnets; the IPv6 overlay has no containment
      # arithmetic in scope (documented in lib/cidr.nix), so its addresses are matched exactly
      # (uniqueness) rather than by subnet. The overlay is asserted against the mesh subnet,
      # which is the overlay by design (the wireguard module treats it as such throughout).
      v4Subnets = lib.filterAttrs (_: subnet: !(lib.hasInfix ":" subnet.cidr)) cfg.subnets;
      outsideSubnet = lib.filter (fact: !(cidrLib.containsV4 v4Subnets.${fact.zone}.cidr fact.value)) (
        lib.concatLists (
          lib.mapAttrsToList (name: device: [
            {
              inherit name;
              value = device.ipv4;
              zone = device.zone;
            }
          ]) (lib.filterAttrs (_: device: v4Subnets ? ${device.zone}) cfg.devices)
        )
        ++ lib.optionals (v4Subnets ? mesh) (
          lib.concatLists (
            lib.mapAttrsToList (name: host: [
              {
                inherit name;
                value = host.wireguardIpv4;
                zone = "mesh";
              }
            ]) (lib.filterAttrs (_: host: host.wireguardIpv4 != null) cfg.hosts)
          )
        )
        ++ lib.concatLists (
          lib.mapAttrsToList
            (name: host: [
              {
                inherit name;
                value = host.ipv4;
                zone = host.zone;
              }
            ])
            (
              lib.filterAttrs (
                _: host:
                host.ipv4 != null
                && (cfg.subnets.${host.zone}.trustLevel or "mesh") != "mesh"
                && v4Subnets ? ${host.zone}
              ) cfg.hosts
            )
        )
        ++ lib.concatLists (
          lib.mapAttrsToList (name: subnet: [
            {
              inherit name;
              value = subnet.gateway;
              zone = name;
            }
          ]) (lib.filterAttrs (name: subnet: subnet.gateway != null && v4Subnets ? ${name}) cfg.subnets)
        )
      );

      v6Subnets = lib.filterAttrs (
        _: subnet: lib.hasInfix ":" subnet.cidr && subnet.trustLevel == "mesh"
      ) cfg.subnets;
      outsideV6Subnet = lib.filter (
        fact: !(lib.any (subnet: cidrLib.containsV6 subnet.cidr fact.value) (lib.attrValues v6Subnets))
      ) v6Facts;
    in
    {
      assertions = [
        {
          assertion = hostsWithBadZone == [ ];
          message = "topology: hosts with an unknown zone (not a my.topology.subnets key): ${lib.concatStringsSep ", " hostsWithBadZone}";
        }
        {
          assertion = devicesWithBadZone == [ ];
          message = "topology: devices with an unknown zone (not a my.topology.subnets key): ${lib.concatStringsSep ", " devicesWithBadZone}";
        }
        {
          assertion = missingSiteHosts == [ ];
          message = "topology: site roles reference unknown hosts: ${lib.concatStringsSep ", " missingSiteHosts}";
        }
        {
          assertion = missingRequiredSiteRoles == [ ];
          message = "topology: site roles are not assigned: ${lib.concatStringsSep ", " (map toString missingRequiredSiteRoles)}";
        }
        {
          assertion = invalidGatewayHosts == { };
          message = "topology: gatewayHost references unknown hosts: ${lib.concatStringsSep ", " (builtins.attrNames invalidGatewayHosts)}";
        }
        {
          assertion = !invalidUpstreamRouter;
          message = "topology: upstreamRouter has no IPv4 address";
        }
        {
          assertion = !invalidPrimaryHub;
          message = "topology: primaryWireguardHub '${cfg.primaryWireguardHub}' is not a declared relay";
        }
        {
          assertion = invalidNtpZones == [ ];
          message = "topology: ntpZones reference unknown subnets: ${lib.concatStringsSep ", " invalidNtpZones}";
        }
        {
          assertion = !invalidDefaultDhcpZone;
          message = "topology: defaultDhcpZone '${toString cfg.defaultDhcpZone}' is not a declared subnet";
        }
        {
          assertion = malformedV4 == [ ];
          message = "topology: malformed IPv4 addresses: ${
            lib.concatStringsSep ", " (map (fact: "${fact.name} (${fact.kind}): ${fact.value}") malformedV4)
          }";
        }
        {
          assertion = malformedV6 == [ ];
          message = "topology: malformed IPv6 overlay addresses: ${
            lib.concatStringsSep ", " (map (fact: "${fact.name}: ${fact.value}") malformedV6)
          }";
        }
        {
          assertion = duplicateV6 == [ ];
          message = "topology: IPv6 overlay addresses claimed more than once: ${lib.concatStringsSep ", " duplicateV6}";
        }
        {
          assertion = malformedCidrs == [ ];
          message = "topology: malformed subnet CIDRs: ${lib.concatStringsSep ", " malformedCidrs}";
        }
        {
          assertion = overlappingSubnets == [ ];
          message = "topology: overlapping subnets: ${
            lib.concatStringsSep ", " (
              map (
                pair:
                "${pair.left} (${cfg.subnets.${pair.left}.cidr}) and ${pair.right} (${cfg.subnets.${pair.right}.cidr})"
              ) overlappingSubnets
            )
          }";
        }
        {
          assertion = duplicateV4 == [ ];
          message = "topology: IPv4 addresses claimed more than once: ${lib.concatStringsSep ", " duplicateV4}";
        }
        {
          assertion = gatewayConflicts == [ ];
          message = "topology: gateway address conflicts: ${lib.concatStringsSep ", " gatewayConflicts}";
        }
        {
          assertion = outsideSubnet == [ ];
          message = "topology: addresses outside their zone's subnet: ${
            lib.concatStringsSep ", " (
              map (fact: "${fact.name}: ${fact.value} not in ${fact.zone}") outsideSubnet
            )
          }";
        }
        {
          assertion = outsideV6Subnet == [ ];
          message = "topology: IPv6 overlay addresses outside all declared IPv6 subnets: ${
            lib.concatStringsSep ", " (map (fact: "${fact.name}: ${fact.value}") outsideV6Subnet)
          }";
        }
      ];

      # Trusted network policy is derived from subnet trust categories, not zone names.
      my.topology.trustedSubnets = lib.mkDefault (
        lib.mapAttrsToList (_: subnet: subnet.cidr) (
          lib.filterAttrs (_: s: s.trustLevel != "guest" && s.trustLevel != "iot") cfg.subnets
        )
      );

      my.topology.announcedZones = lib.filter (
        zone:
        cfg.subnets.${zone}.trustLevel != "guest"
        && cfg.subnets.${zone}.trustLevel != "mesh"
        && lib.any (device: device.zone == zone && device.ipv4 != null) (lib.attrValues cfg.devices)
      ) (lib.attrNames cfg.subnets);

      my.topology.trustLevels = trustLevelNames;

      my.topology.lanZones = lib.attrNames (
        lib.filterAttrs (_: subnet: subnet.trustLevel != "mesh" && subnet.trustLevel != "guest") cfg.subnets
      );

      my.topology.sourcesByTrust = builtins.foldl' (
        acc: host:
        let
          level = (cfg.subnets.${host.zone} or { }).trustLevel or host.zone;
          sources =
            lib.optional (host.ipv4 != null) "${host.ipv4}/32"
            ++ lib.optional (host.wireguardIpv4 != null) "${host.wireguardIpv4}/32"
            ++ lib.optional (host.wireguardIpv6 != null) "${host.wireguardIpv6}/128";
        in
        acc // { ${level} = (acc.${level} or [ ]) ++ sources; }
      ) { } (lib.attrValues cfg.hosts);
    };
}
