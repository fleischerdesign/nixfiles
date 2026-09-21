# features/system/networking/topology/default.nix
# Declarative network topology, subnet zoning, and host address registry (RFC 1918 / nixfiles 2.0).
{
  config,
  lib,
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
      trustLevel = lib.mkOption {
        type = trustLevel;
        description = "Trust level within the Bell-LaPadula security lattice";
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
      zone = lib.mkOption {
        type = trustLevel;
        description = "Subnet zone membership of the host";
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
    };
  };

  # Submodule for IoT/microcontroller device definition
  deviceSubmodule = lib.types.submodule {
    options = {
      zone = lib.mkOption {
        type = trustLevel;
        default = "iot";
        description = "Subnet zone membership of the device";
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
      type = lib.types.str;
      default = "vyrx.de";
      description = "Primary root domain for all cluster services and DNS zones";
    };

    # Single source of truth for the public ingress host. The Caddy ingress engine and the
    # Cloudflare DNS projection both read this, so ingress responsibility is declared once
    # (docs/architecture.md §7.1).
    ingressHost = lib.mkOption {
      type = lib.types.str;
      default = "cld-edge-01";
      description = "Topology host that terminates public ingress traffic.";
    };

    # The host that routes the home LAN, declared the way the ingress host is. It is the next hop for
    # a node that reaches a home zone from outside, the home door of the resolver, and the host that
    # has to allow forwarding into those zones. Which zones it carries follows from the inventory
    # (`announcedZones`), so no zone list is maintained next to this declaration.
    lanRouter = lib.mkOption {
      type = lib.types.str;
      default = "hom-srv-01";
      description = "Topology host that routes the home LAN.";
    };

    # The hosts that serve DNS. They generate the same zones from this inventory, so a name has one
    # answer wherever it is asked, and nothing has to be replicated between them at runtime. Each one is
    # a door for the mesh: a node that is not fixed at home can ask any of them, which is what removes
    # the single point of failure - and a host that is declared here but does not run the resolver is a
    # build failure, not a surprise during an outage.
    resolverHosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "hom-srv-01"
        "cld-edge-01"
      ];
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
        default = "VYRX";
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

  # Everything reads my.topology directly. The compatibility shim that mirrored it under
  # The legacy compatibility shim is gone: it renamed fields (ipv4 -> localIp,
  # wireguardIpv4 -> wireguardIpv4) and its hosts lacked ipv4 entirely, so a consumer filtering on
  # that field silently matched nothing.
  config = {
    # Default subnet taxonomy as specified in docs/architecture.md (RFC 1918 10.10.0.0/16 Supernet).
    #
    # There are no VLANs: the zones are subnets on one flat L2 behind a single NIC, separated by
    # routing policy rather than by an 802.1Q tag. The per-subnet `vlan` field that used to sit here
    # was read by nobody while looking like evidence of segmentation - if VLANs are ever built, the
    # field comes back together with the code that reads it.
    my.topology.subnets = lib.mkDefault {
      infra = {
        cidr = "10.10.10.0/24";
        gateway = "10.10.10.1";
        trustLevel = "infra";
        description = "Core servers, managed networking, gateways, and storage";
      };
      corp = {
        cidr = "10.10.20.0/24";
        gateway = "10.10.20.1";
        trustLevel = "corp";
        description = "Trusted employee workstations, laptops, and administrative personal devices";
      };
      iot = {
        cidr = "10.10.30.0/24";
        gateway = "10.10.30.1";
        trustLevel = "iot";
        description = "Isolated microcontrollers, 3D printers, ESPHome, smart home devices";
      };
      mesh = {
        cidr = "10.10.100.0/24";
        gateway = "10.10.100.1";
        trustLevel = "mesh";
        description = "Kernel-WireGuard ChaCha20 overlay mesh connecting cloud VPS and home nodes (IPv4)";
      };
      mesh-ipv6 = {
        cidr = "fd10:1000:100::/64";
        trustLevel = "mesh";
        description = "Kernel-WireGuard RFC 4193 ULA overlay mesh connecting cloud VPS and home nodes (IPv6)";
      };
      guest = {
        cidr = "10.10.99.0/24";
        gateway = "10.10.99.1";
        trustLevel = "guest";
        description = "Isolated guest network with direct internet transit only";
      };
    };

    # Default host registry conforming to RFC 1178 Enterprise Taxonomy
    my.topology.hosts = lib.mkDefault {
      cld-edge-01 = {
        zone = "mesh";
        ipv4 = "173.249.22.211";
        gateway = "173.249.22.1";
        interface = "eth0";
        wireguardIpv4 = "10.10.100.1";
        wireguardIpv6 = "fd10:1000:100::1";
        wireguardPublicKey = "xaW5sos7b7wPXsjl4U6UqsaHl9l+Y1F013DDJ4kioEg=";
        wireguardRelay = true;
        hostType = "server";
      };

      cld-ops-01 = {
        zone = "mesh";
        ipv4 = "37.114.55.91";
        gateway = "37.114.55.1";
        interface = "eth0";
        wireguardIpv4 = "10.10.100.2";
        wireguardIpv6 = "fd10:1000:100::2";
        wireguardPublicKey = "DBU0HRrBeIXZFokauPXfsYA3i7feCov154VbkAdwlTM=";
        wireguardRelay = true;
        hostType = "server";
      };

      hom-srv-01 = {
        zone = "infra";
        ipv4 = "10.10.10.10";
        # No per-host gateway: `subnets.infra.gateway` is the single declaration for this zone. The
        # field survives only as the override for hosts whose uplink is not a zone gateway at all -
        # the VPS hosts, which sit behind their provider's router.
        gateway = null;
        interface = "enp2s0";
        wireguardIpv4 = "10.10.100.10";
        wireguardIpv6 = "fd10:1000:100::10";
        wireguardPublicKey = "j80spw+2+Ojz51aKAytPdCZwFOc64yNOR05rAcXOESE=";
        hostType = "server";
      };

      hom-wrk-01 = {
        zone = "corp";
        ipv4 = "10.10.20.10";
        # No per-host gateway: the zone's gateway (10.10.20.1) is the one that lives inside the
        # subnet and is therefore the only one that can be installed as a default route.
        gateway = null;
        interface = "enp0s31f6";
        wireguardIpv4 = "10.10.100.20";
        wireguardIpv6 = "fd10:1000:100::20";
        wireguardPublicKey = "y9CMim/6IWIKdIztKJQh5BR7R2ygjYwCjjEvgJQSLT0=";
        hostType = "workstation";
      };

      mob-nb-01 = {
        zone = "corp";
        ipv4 = null; # Roaming DHCP
        gateway = null;
        wireguardIpv4 = "10.10.100.30";
        wireguardIpv6 = "fd10:1000:100::30";
        wireguardPublicKey = "J+PERS3HY0OcfXKk4qFnJWtgLy4afh3cXX8fkuKelx0=";
        hostType = "client";
      };

      # A phone joins the mesh as a client node, not a managed host: it has an overlay identity and no
      # NixOS configuration. `mob-nb-01` is the same class of node; this one's WireGuard configuration
      # is rendered from the topology and its SOPS key instead of `networking.wireguard.interfaces`.
      # The name follows `<class>-<role>-<nn>` (docs/architecture.md §2), not a person.
      mob-ph-01 = {
        zone = "corp";
        ipv4 = null; # Roaming: no LAN address, so it carries every delivered zone over the mesh.
        gateway = null;
        wireguardIpv4 = "10.10.100.40";
        wireguardIpv6 = "fd10:1000:100::40";
        wireguardPublicKey = "33yImKTdRMyeM8yYgabBLbZ1xLIMife6CGsSMCicmjo=";
        hostType = "client";
      };

      # Embedded targets as specified in docs/embedded.md
      hom-rt-01 = {
        zone = "infra";
        ipv4 = "10.10.10.1";
        hostType = "embedded";
      };

      hom-ap-01 = {
        zone = "infra";
        ipv4 = "10.10.10.20";
        mac = "7c:f1:7e:6a:b0:82"; # wired MAC: leases the declared address from Kea
        hostType = "embedded";
      };
    };

    # Default IoT devices conforming to RFC 1178 Enterprise Taxonomy
    my.topology.devices = lib.mkDefault {
      # Peripheral hardware that is not a microcontroller.
      hom-prn-01 = {
        zone = "iot";
        mac = "80:ce:62:8a:7c:06"; # HP MFP, hostname hp8a7c05; leases its iot address from Kea
        ipv4 = "10.10.30.19";
        description = "HP Multifunktionsdrucker/Scanner (hp8a7c05), iot-Zone";
        # The one thing a mesh member may use on this device: IPP. Its web interface (80/443) is
        # deliberately *not* declared - it stays reachable inside the LAN, where the segment is flat and
        # no rule of ours applies anyway, and it is closed from the mesh, which is where the exposure
        # would otherwise grow without anyone deciding it. Printing is the household's use case: the
        # servers and the family's own devices, not the cloud.
        endpoints.ipp = {
          port = 631;
          protocol = "tcp";
          from = [
            "infra"
            "corp"
          ];
          description = "Drucken aus dem Mesh (Server und Haushalt) - nicht aus der Cloud-Zone";
        };
      };
      # Enterprise Relais-Aktoren (Sonoff Basic ESP8266 Inline-Relais)
      #
      # They declare no endpoint, and that is a decision rather than an omission: the ESPHome dashboard
      # that talks to them runs on `hom-srv-01`, which shares their segment, so its traffic is never
      # routed; and a relay's API reachable over the mesh would be reachable by every member. Nothing
      # needs it, so nothing may use it.
      hom-rly-01 = {
        zone = "iot";
        ipv4 = "10.10.30.11";
        mac = "8c:ce:4e:0c:d7:98";
        platform = "esp8266";
        board = "esp01_1m";
        description = "Arbeitszimmer Relais";
      };

      hom-rly-02 = {
        zone = "iot";
        ipv4 = "10.10.30.12";
        mac = "70:03:9f:64:8e:b0";
        platform = "esp8266";
        board = "esp01_1m";
        description = "Bad Relais";
      };

      hom-rly-03 = {
        zone = "iot";
        ipv4 = "10.10.30.13";
        mac = "e8:68:e7:44:b3:a1";
        platform = "esp8266";
        board = "esp01_1m";
        description = "Ender 3D-Drucker Relais";
      };

      hom-rly-06 = {
        zone = "iot";
        ipv4 = "10.10.30.16";
        mac = "8c:ce:4e:0c:e1:70";
        platform = "esp8266";
        board = "esp01_1m";
        description = "Küche Relais";
      };

      hom-rly-07 = {
        zone = "iot";
        ipv4 = "10.10.30.17";
        mac = "8c:ce:4e:0c:da:e5";
        platform = "esp8266";
        board = "esp01_1m";
        description = "Schlafzimmer Relais";
      };

      hom-rly-08 = {
        zone = "iot";
        ipv4 = "10.10.30.18";
        mac = "8c:ce:4e:0c:de:cb";
        platform = "esp8266";
        board = "esp01_1m";
        description = "Sofa Relais";
      };
    };

    # Synthesize trustedSubnets automatically from subnets where trustLevel != "guest" and trustLevel != "iot"
    my.topology.trustedSubnets = lib.mkDefault (
      lib.mapAttrsToList (_: subnet: subnet.cidr) (
        lib.filterAttrs (_: s: s.trustLevel != "guest" && s.trustLevel != "iot") cfg.subnets
      )
    );

    my.topology.announcedZones = lib.filter (
      zone:
      zone != "guest"
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
