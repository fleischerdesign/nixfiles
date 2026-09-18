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
        wireguardIpv4 = "10.10.100.1";
        wireguardIpv6 = "fd10:1000:100::1";
        wireguardRelay = true;
        hostType = "server";
        domain = "edge.vyrx.de";
      };

      cld-ops-01 = {
        zone = "mesh";
        ipv4 = "37.114.55.91";
        gateway = "37.114.55.1";
        wireguardIpv4 = "10.10.100.2";
        wireguardIpv6 = "fd10:1000:100::2";
        wireguardRelay = true;
        hostType = "server";
        domain = "ops.vyrx.de";
      };

      hom-srv-01 = {
        zone = "infra";
        ipv4 = "10.10.10.10";
        gateway = "10.10.10.1";
        wireguardIpv4 = "10.10.100.10";
        wireguardIpv6 = "fd10:1000:100::10";
        hostType = "server";
        domain = "srv.lan.vyrx.de";
      };

      hom-wrk-01 = {
        zone = "corp";
        ipv4 = "10.10.20.10";
        gateway = "10.10.10.10";
        wireguardIpv4 = "10.10.100.20";
        wireguardIpv6 = "fd10:1000:100::20";
        hostType = "workstation";
        domain = "wrk.lan.vyrx.de";
      };

      mob-nb-01 = {
        zone = "corp";
        ipv4 = null; # Roaming DHCP
        gateway = null;
        wireguardIpv4 = "10.10.100.30";
        wireguardIpv6 = "fd10:1000:100::30";
        hostType = "client";
        domain = "nb.lan.vyrx.de";
      };

      # Embedded targets as specified in EMBEDDED.md
      hom-rt-01 = {
        zone = "infra";
        ipv4 = "10.10.10.1";
        hostType = "embedded";
        domain = "rt.lan.vyrx.de";
      };

      hom-ap-01 = {
        zone = "infra";
        ipv4 = "10.10.10.20";
        hostType = "embedded";
        domain = "ap.lan.vyrx.de";
      };
    };

    # Default IoT devices
    my.topology.devices = lib.mkDefault {
      living-room-sensor = {
        zone = "iot";
        ipv4 = "10.10.30.25";
        mac = "24:6F:28:A1:B2:C3";
        platform = "esp32";
        board = "esp32dev";
        description = "Living Room Climate & Multi-Sensor";
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
        hostType = if h.hostType == "workstation" || h.hostType == "client" then "client" else "server";
        gateway = h.gateway;
      }) cfg.hosts
    );
    my.features.system.networking.topology.trustedSubnets = lib.mkDefault cfg.trustedSubnets;
  };
}
