# features/system/networking/static/default.nix
# Topology-driven static addressing.
#
# Single source of truth: my.topology.hosts.<host> — interface, ipv4 and gateway.
# Nothing here hardcodes an interface name (the previous version addressed eth0, which
# silently did nothing on hosts whose NIC is enp2s0) or a public resolver (which would
# bypass Blocky's split horizon).
#
# NetworkManager must not own an interface that this module addresses, so the interface is
# declared unmanaged: exactly one system may own a NIC.
{
  config,
  lib,
  ...
}:
let
  cfg = config.my.features.system.networking.static;
  topology = config.my.topology;
  hostTopology = topology.hosts.${config.networking.hostName} or null;

  interface = hostTopology.interface or null;

  targetAddresses = lib.optional (hostTopology != null && hostTopology.ipv4 != null) {
    address = hostTopology.ipv4;
    prefixLength = 24;
  };

  # The host's own declaration wins; the zone gateway is only a fallback. The order is not
  # cosmetic: a VPS declares its provider's router (a public address) while its zone is `mesh`, whose
  # gateway is the mesh address - so letting the zone win handed the edge a default route via itself
  # and took it off the network. A zone gateway is the right default for a host that has no uplink of
  # its own, never an override for one that does.
  zoneGateway =
    if hostTopology == null then
      null
    else
      (config.my.topology.subnets.${config.my.topology.hosts.${config.networking.hostName}.zone} or { })
      .gateway or null;

  gateway =
    if hostTopology != null && hostTopology.gateway != null then hostTopology.gateway else zoneGateway;

  active =
    cfg.enable
    && hostTopology != null
    && interface != null
    && hostTopology.ipv4 != null
    && (hostTopology.gateway != null || zoneGateway != null);
in
{
  options.my.features.system.networking.static = {
    enable = lib.mkEnableOption "Topology-driven static addressing";
  };

  config = lib.mkIf active {
    networking.useDHCP = false;

    networking.interfaces.${interface} = {
      useDHCP = false;
      ipv4.addresses = targetAddresses;
    };

    # null means "no default route", which is not a state we want to reach silently.
    networking.defaultGateway = gateway;

    # A default, not the answer: the module that owns resolution
    # (features/system/networking/resolver) replaces this list where it is enabled, and the
    # declaration is kept as a default so a fleet can move over one host at a time.
    networking.nameservers = lib.mkDefault config.my.topology.resolvers;

    # ...and that declaration has to reach the component that actually owns
    # /etc/resolv.conf. openresolv does (`networking.resolvconf.enable` defaults to true on
    # NixOS) and it does not read `networking.nameservers` - that option is consumed by
    # systemd-resolved and NetworkManager only, so on these hosts it was inert and the file
    # kept whatever wrote it last: a stale DHCP lease left the uplink's nameservers first and
    # name resolution timed out (measured 2026-09-21 on hom-srv-01, and hom-wrk-01 pointed at
    # a foreign resolver). Both projections come from the one list in the inventory.
    networking.resolvconf.extraConfig = "name_servers='${lib.concatStringsSep " " config.my.topology.resolvers}'";

    # Exactly one owner per NIC.
    networking.networkmanager.unmanaged = [ interface ];
  };
}
