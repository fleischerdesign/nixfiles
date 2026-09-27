# inventory/subnets.nix - the site's network segments, the single authoritative declaration.
#
# Composed explicitly by lib/mk-system.nix, never auto-discovered. Extension policy: add a key
# to extend the map; override a single key (my.topology.subnets.<zone>.<field>) to correct one
# fact. These are plain definitions on purpose - a whole-map mkDefault here would let an
# ordinary-priority map silently replace the inventory instead of extending one entry.
#
# Subnet taxonomy as specified in docs/architecture.md (RFC 1918 10.10.0.0/16 Supernet).
#
# There are no VLANs: the zones are subnets on one flat L2 behind a single NIC, separated by
# routing policy rather than by an 802.1Q tag. The per-subnet `vlan` field that used to sit here
# was read by nobody while looking like evidence of segmentation - if VLANs are ever built, the
# field comes back together with the code that reads it.
_: {
  my.topology.subnets = {
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
}
