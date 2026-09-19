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
      vlan = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "802.1Q VLAN ID (null for untagged / mesh overlay)";
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
      domain = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Primary canonical domain or node FQDN";
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
        type = lib.types.enum [
          "esp32"
          "esp8266"
          "rp2040"
        ];
        default = "esp32";
        description = "Microcontroller platform architecture";
      };
      board = lib.mkOption {
        type = lib.types.str;
        default = "esp32dev";
        description = "Hardware board definition target";
      };
      description = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Human-readable description of device function";
      };
      domain = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional canonical FQDN for local DNS resolution";
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

    trustedSubnets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Subnets with elevated trust level, synthesized for firewall and IPS whitelisting";
    };
  };

  # Compatibility shim for legacy options during migration phase
  options.my.features.system.networking.topology = {
    enable = lib.mkEnableOption "Legacy topology module compatibility shim";
    hosts = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Shim pointing to my.topology.hosts";
    };
    trustedSubnets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Shim pointing to my.topology.trustedSubnets";
    };
  };

  config = {
    # Default subnet taxonomy as specified in ARCHITECTURE.md (RFC 1918 10.10.0.0/16 Supernet)
    my.topology.subnets = lib.mkDefault {
      infra = {
        cidr = "10.10.10.0/24";
        vlan = 10;
        trustLevel = "infra";
        description = "Core servers, managed networking, gateways, and storage";
      };
      corp = {
        cidr = "10.10.20.0/24";
        vlan = 20;
        trustLevel = "corp";
        description = "Trusted employee workstations, laptops, and administrative personal devices";
      };
      iot = {
        cidr = "10.10.30.0/24";
        vlan = 30;
        trustLevel = "iot";
        description = "Isolated microcontrollers, 3D printers, ESPHome, smart home devices";
      };
      mesh = {
        cidr = "10.10.100.0/24";
        vlan = null;
        trustLevel = "mesh";
        description = "Kernel-WireGuard ChaCha20 overlay mesh connecting cloud VPS and home nodes (IPv4)";
      };
      mesh-ipv6 = {
        cidr = "fd10:1000:100::/64";
        vlan = null;
        trustLevel = "mesh";
        description = "Kernel-WireGuard RFC 4193 ULA overlay mesh connecting cloud VPS and home nodes (IPv6)";
      };
      guest = {
        cidr = "10.10.99.0/24";
        vlan = 99;
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
        domain = "edge.vyrx.de";
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
        domain = "ops.vyrx.de";
      };

      hom-srv-01 = {
        zone = "infra";
        ipv4 = "10.10.10.10";
        gateway = "10.10.10.1";
        interface = "enp2s0";
        wireguardIpv4 = "10.10.100.10";
        wireguardIpv6 = "fd10:1000:100::10";
        wireguardPublicKey = "j80spw+2+Ojz51aKAytPdCZwFOc64yNOR05rAcXOESE=";
        hostType = "server";
        domain = "srv.lan.vyrx.de";
        # TEMPORARY (subnet migration): stay reachable on the old network until the
        # FRITZ!Box has moved to 10.10.10.1/24 and DHCP is handed over to Kea.
        migration = {
          addresses = [ "192.168.178.27/24" ];
          gateway = "192.168.178.1";
        };
      };

      hom-wrk-01 = {
        zone = "corp";
        ipv4 = "10.10.20.10";
        gateway = "10.10.10.10";
        wireguardIpv4 = "10.10.100.20";
        wireguardIpv6 = "fd10:1000:100::20";
        wireguardPublicKey = "y9CMim/6IWIKdIztKJQh5BR7R2ygjYwCjjEvgJQSLT0=";
        hostType = "workstation";
        domain = "wrk.lan.vyrx.de";
      };

      mob-nb-01 = {
        zone = "corp";
        ipv4 = null; # Roaming DHCP
        gateway = null;
        wireguardIpv4 = "10.10.100.30";
        wireguardIpv6 = "fd10:1000:100::30";
        wireguardPublicKey = "J+PERS3HY0OcfXKk4qFnJWtgLy4afh3cXX8fkuKelx0=";
        hostType = "client";
        domain = "nb.lan.vyrx.de";
      };

      # Embedded targets as specified in EMBEDDED.md
      hom-rt-01 = {
        zone = "infra";
        ipv4 = "10.10.10.1";
        hostType = "embedded";
        domain = "rt.lan.vyrx.de";
        # TEMPORARY (subnet migration): the box still answers on the old LAN address until it
        # is re-addressed. Reported by I11 and removed at teardown (DEPLOYMENT §14).
        migration = {
          addresses = [ "192.168.178.1/24" ];
        };
      };

      hom-ap-01 = {
        zone = "infra";
        ipv4 = "10.10.10.20";
        mac = "7c:f1:7e:6a:b0:82"; # wired MAC: leases the declared address from Kea
        hostType = "embedded";
        domain = "ap.lan.vyrx.de";
        # TEMPORARY (subnet migration): the AP still answers on the old LAN address until it is
        # re-addressed. Reported by I11 and removed at teardown (DEPLOYMENT §14).
        migration = {
          addresses = [ "192.168.178.54/24" ];
        };
      };
    };

    # Default IoT devices conforming to RFC 1178 Enterprise Taxonomy
    my.topology.devices = lib.mkDefault {
      # Enterprise Relais-Aktoren (Sonoff Basic ESP8266 Inline-Relais)
      hom-rly-01 = {
        zone = "iot";
        ipv4 = "10.10.30.11";
        mac = "8c:ce:4e:0c:d7:98";
        platform = "esp8266";
        board = "esp01_1m";
        description = "Arbeitszimmer Relais";
        domain = "rly-01.iot.vyrx.de";
      };

      hom-rly-02 = {
        zone = "iot";
        ipv4 = "10.10.30.12";
        mac = "70:03:9f:64:8e:b0";
        platform = "esp8266";
        board = "esp01_1m";
        description = "Bad Relais";
        domain = "rly-02.iot.vyrx.de";
      };

      hom-rly-03 = {
        zone = "iot";
        ipv4 = "10.10.30.13";
        mac = "e8:68:e7:44:b3:a1";
        platform = "esp8266";
        board = "esp01_1m";
        description = "Ender 3D-Drucker Relais";
        domain = "rly-03.iot.vyrx.de";
      };

      hom-rly-06 = {
        zone = "iot";
        ipv4 = "10.10.30.16";
        mac = "8c:ce:4e:0c:e1:70";
        platform = "esp8266";
        board = "esp01_1m";
        description = "Küche Relais";
        domain = "rly-06.iot.vyrx.de";
      };

      hom-rly-07 = {
        zone = "iot";
        ipv4 = "10.10.30.17";
        mac = "8c:ce:4e:0c:da:e5";
        platform = "esp8266";
        board = "esp01_1m";
        description = "Schlafzimmer Relais";
        domain = "rly-07.iot.vyrx.de";
      };

      hom-rly-08 = {
        zone = "iot";
        ipv4 = "10.10.30.18";
        mac = "8c:ce:4e:0c:de:cb";
        platform = "esp8266";
        board = "esp01_1m";
        description = "Sofa Relais";
        domain = "rly-08.iot.vyrx.de";
      };
    };

    # Synthesize trustedSubnets automatically from subnets where trustLevel != "guest" and trustLevel != "iot"
    my.topology.trustedSubnets = lib.mkDefault (
      lib.mapAttrsToList (_: subnet: subnet.cidr) (
        lib.filterAttrs (_: s: s.trustLevel != "guest" && s.trustLevel != "iot") cfg.subnets
      )
    );

    # Populate legacy shim
    my.features.system.networking.topology.hosts = lib.mkDefault (
      lib.mapAttrs (_name: h: {
        tailscaleIp = h.wireguardIpv4; # Point legacy references to wireguard IP during transition
        wireguardIpv6 = h.wireguardIpv6;
        localIp = h.ipv4;
        domain = h.domain;
        interface = h.interface;
        migration = h.migration;
        hostType = if h.hostType == "workstation" || h.hostType == "client" then "client" else "server";
        gateway = h.gateway;
      }) cfg.hosts
    );
    my.features.system.networking.topology.trustedSubnets = lib.mkDefault cfg.trustedSubnets;
  };
}
