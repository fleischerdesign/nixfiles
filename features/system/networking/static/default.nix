# features/system/networking/static/default.nix
# Topology-driven static addressing.
#
# Single source of truth: my.topology.hosts.<host> — interface, ipv4, gateway and the
# temporary `migration` block. Nothing here hardcodes an interface name (the previous
# version addressed eth0, which silently did nothing on hosts whose NIC is enp2s0) or a
# public resolver (which would bypass Blocky's split horizon).
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
  topology = config.my.features.system.networking.topology;
  hostTopology = topology.hosts.${config.networking.hostName} or null;

  interface = hostTopology.interface or null;

  # Parse a CIDR string into the address submodule shape NixOS expects.
  parseCidr =
    cidr:
    let
      parts = lib.splitString "/" cidr;
    in
    {
      address = builtins.elemAt parts 0;
      prefixLength = lib.toInt (builtins.elemAt parts 1);
    };

  targetAddresses = lib.optional (hostTopology != null && hostTopology.localIp != null) {
    address = hostTopology.localIp;
    prefixLength = 24;
  };

  migration =
    if hostTopology == null then
      {
        addresses = [ ];
        gateway = null;
      }
    else
      hostTopology.migration;

  # While migrating, the old gateway must stay in charge - the new one may not exist yet.
  gateway =
    if migration.gateway != null then
      migration.gateway
    else if hostTopology != null then
      hostTopology.gateway
    else
      null;

  active =
    cfg.enable
    && hostTopology != null
    && interface != null
    && hostTopology.localIp != null
    && (hostTopology.gateway != null || migration.gateway != null);
in
{
  options.my.features.system.networking.static = {
    enable = lib.mkEnableOption "Topology-driven static addressing";
  };

  config = lib.mkIf active {
    networking.useDHCP = false;

    networking.interfaces.${interface} = {
      useDHCP = false;
      ipv4.addresses = targetAddresses ++ map parseCidr migration.addresses;
    };

    # null means "no default route", which is not a state we want to reach silently.
    networking.defaultGateway = gateway;

    # Blocky owns the split horizon; the uplink is only the fallback.
    networking.nameservers = config.my.topology.resolvers;

    # Exactly one owner per NIC.
    networking.networkmanager.unmanaged = [ interface ];
  };
}
