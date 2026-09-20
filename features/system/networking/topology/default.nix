# features/system/networking/topology/default.nix
# Declarative network topology, subnet zoning, and host address registry (RFC 1918 / nixfiles 2.0).
{
  config,
  lib,
  ...
}:

let
  cfg = config.my.topology;

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
        type = lib.types.enum [
          "infra"
          "corp"
          "mesh"
          "iot"
          "guest"
        ];
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
        type = lib.types.enum [
          "infra"
          "corp"
          "mesh"
          "iot"
          "guest"
        ];
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

      # TEMPORARY migration aid. Keeps a host reachable on the OLD network while the LAN is
      # being re-addressed, so a cutover can never lock us out. Must be emptied (addresses)
      # and nulled (gateway) once the migration is complete.
      migration = {
        addresses = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [ "192.168.178.27/24" ];
          description = "Additional addresses (CIDR) kept during a subnet migration.";
        };

        gateway = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "192.168.178.1";
          description = "Default gateway to use while migrating (the old uplink).";
        };

        ssid = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "Ancoris";
          description = ''
            WLAN name this device still radiates/joins under its old identity. Devices that must
            stay reachable across the rename store both this and the fleet SSID, so the rename
            locks nothing out.
          '';
        };
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
      lanGateway = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          Zones this host delivers into the mesh, written as zone names - the CIDRs are read from
          `my.topology.subnets`, so an address is never written twice. The mesh carries the overlay
          on its own, so a roaming client needs this announcement to reach anything behind it. A
          zone may be delivered by one host only: cryptokey routing has exactly one owner per
          prefix. A host that sits inside a zone installs no mesh route for it, because it reaches
          that zone directly.
        '';
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
        type = lib.types.enum [
          "infra"
          "corp"
          "mesh"
          "iot"
          "guest"
        ];
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
    # (ARCHITECTURE.md §8.1).
    ingressHost = lib.mkOption {
      type = lib.types.str;
      default = "cld-edge-01";
      description = "Topology host that terminates public ingress traffic.";
    };

    resolvers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "10.10.10.10"
        "10.10.10.1"
      ];
      description = ''
        Authoritative resolvers handed to hosts and DHCP clients: the local Blocky instance
        first (it owns the split horizon), the uplink router as fallback. Never public
        resolvers - they would bypass split horizon and the internal zones.
      '';
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
          microcontrollers store it, so the two cannot drift apart. A transitional old name lives
          in the device's `migration.ssid` and disappears at teardown.
        '';
      };
    };

    trustedSubnets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Subnets with elevated trust level, synthesized for firewall and IPS whitelisting";
    };
  };

  # Everything reads my.topology directly. The compatibility shim that mirrored it under
  # The legacy compatibility shim is gone: it renamed fields (ipv4 -> localIp,
  # wireguardIpv4 -> wireguardIpv4) and its hosts lacked ipv4 entirely, so a consumer filtering on
  # that field silently matched nothing.
  config = {
    # Default subnet taxonomy as specified in ARCHITECTURE.md (RFC 1918 10.10.0.0/16 Supernet).
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
        # This host routes the home LAN, so it is the one that delivers those zones into the mesh
        # (DEPLOYMENT.md 10). The announcement replaced Tailscale's subnet router; without it a
        # roaming client reaches the mesh but none of the services behind it. `guest` is absent on
        # purpose: no host carries that zone, so announcing it would route traffic into a hole.
        lanGateway = [
          "infra"
          "corp"
          "iot"
        ];
        # TEMPORARY (subnet migration): stay reachable on the old network until the
        # FRITZ!Box has moved to 10.10.10.1/24 and DHCP is handed over to Kea.
        migration = {
          addresses = [ "192.168.178.27/24" ];
          # Cleared: the FRITZ!Box has moved to 10.10.10.1 and is now the ordinary uplink again.
          # Keeping the old default route would cut the server off the moment the box moves.
          gateway = null;
        };
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
        # TEMPORARY (subnet migration): the old address stays until the new configuration has
        # proven itself, and it is what keeps this host reachable if the switch goes wrong.
        migration = {
          addresses = [ "192.168.178.30/24" ];
        };
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

      # Embedded targets as specified in EMBEDDED.md
      hom-rt-01 = {
        zone = "infra";
        ipv4 = "10.10.10.1";
        hostType = "embedded";
        # The migration block was removed on 2026-09-20, after measurement: the box answers on
        # 10.10.10.1 (ICMP, 80 and 443 open, and the whole fleet's default route runs through it)
        # and it no longer answers on its old LAN address. The fritzbox reconciler derives its target
        # address from this block, so keeping the dead one meant addressing the box where it cannot
        # be reached; with the block gone the schema default (empty) makes it use the ipv4 above.
      };

      hom-ap-01 = {
        zone = "infra";
        ipv4 = "10.10.10.20";
        mac = "7c:f1:7e:6a:b0:82"; # wired MAC: leases the declared address from Kea
        hostType = "embedded";
        # The address half of the migration is finished: the access point leases 10.10.10.20 from
        # Kea through the infra class and no longer answers on its old LAN address (measured silent). The
        # tplink-ap reconciler derives its target address from this block, so the dead address is
        # gone and the reconciler addresses the ipv4 above again. What remains is the WiFi half,
        # which is not an address at all: the old SSID the ESP firmware still carries as a second
        # network so the relays survive that rename. It goes when the relays are reflashed without
        # it.
        migration = {
          ssid = "Ancoris";
        };
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
      };
      # Enterprise Relais-Aktoren (Sonoff Basic ESP8266 Inline-Relais)
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
  };
}
