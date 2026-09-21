# features/system/networking/resolver/default.nix - how a host resolves
#
# Every host resolves through the resolver in the inventory, never through whatever a network
# hands it. The resolver has two doors (`features/services/dns`): the home door on the delivery
# point's own address, reached over the home LAN, and the mesh door on its overlay address,
# reached inside WireGuard. Both are read from the inventory - the host that routes the home LAN
# is the host that answers inside it - so no address is written twice.
#
# The component is systemd-resolved, and not by taste: its global server list *is*
# `networking.nameservers` (nixos/modules/system/boot/resolved.nix), it turns openresolv off
# itself while keeping the `resolvconf` compatibility shim, and it tracks which server answers -
# which is what lets a roaming host list two doors and pay one probe, not a timeout per query.
{
  config,
  lib,
  ...
}:
let
  cfg = config.my.features.system.networking.resolver;
  topology = config.my.topology;
  ownHost = topology.hosts.${config.networking.hostName} or null;

  # The host that routes the home LAN is declared once (`my.topology.lanRouter`); its own address is the
  # home door. Every host the inventory declares as a resolver serves the same zones - they are generated
  # from the same inventory - so its overlay address is a door for anyone inside the mesh, and a node
  # that is not fixed at home survives the home resolver being down.
  deliveryHost = topology.hosts.${topology.lanRouter} or null;
  homeDoor = if deliveryHost == null then null else deliveryHost.ipv4;

  # The mesh side of every declared resolver, the one that routes the home LAN first: it sits closest to
  # the zones it delivers. That order is derived from the fact, not taken from the order of a list.
  meshDoors =
    let
      overlayOf = name: (topology.hosts.${name} or { }).wireguardIpv4 or null;
      doors = lib.filter (d: d != null) (map overlayOf (topology.resolverHosts or [ ]));
      nearest = if deliveryHost == null then null else deliveryHost.wireguardIpv4;
    in
    lib.optionals (nearest != null && builtins.elem nearest doors) [ nearest ]
    ++ lib.filter (door: door != nearest) doors;

  # A host that has its own fixed address in a home zone *is* in the home LAN and stays there, so the
  # home door is the whole answer. Offering it a mesh door as a second would be a liability rather than a
  # fallback: systemd-resolved keeps using the server that answered once a first one failed until its
  # probe sees it again (measured), so one failed probe would move a home host onto the overlay plane and
  # run its LAN lookups - and the LAN traffic that follows them - out through the WAN. A host in a home
  # zone *without* a fixed address roams: the home door first, then the mesh, where a resolver that is
  # not the home one can still answer while the home is unreachable. A host in the mesh zone (a cloud
  # host) is never at home.
  homeZone = ownHost != null && builtins.elem (ownHost.zone or "") topology.lanZones;
  fixedAtHome = homeZone && (ownHost.ipv4 or null) != null;
  mayRoam = homeZone && !fixedAtHome;
  doors = lib.unique (
    lib.filter (d: d != null) (
      if fixedAtHome then
        [ homeDoor ]
      else if mayRoam then
        [ homeDoor ] ++ meshDoors
      else
        meshDoors
    )
  );
in
{
  options.my.features.system.networking.resolver = {
    enable = lib.mkEnableOption "Resolving through the resolver in the inventory (systemd-resolved)";
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = doors != [ ];
        message = "Resolver: no door could be derived (the topology declares no host that routes the home LAN).";
      }
    ];

    # The one place a host learns how to resolve.
    networking.nameservers = doors;

    services.resolved = {
      enable = true;
      settings.Resolve = {
        # systemd-resolved's own default is a public resolver list: a fallback that knows none of
        # our names, and a silent one. Emptying it is what makes "our resolver only" true.
        FallbackDNS = "";
        # All names go to the doors above, so a link's DHCP-provided resolver - a foreign network,
        # the uplink - is never used. A search domain a link provides still completes unqualified
        # names.
        Domains = "~.";
      };
    };

    # NetworkManager feeds the link's DNS into systemd-resolved instead of writing resolv.conf.
    networking.networkmanager.dns = "systemd-resolved";
  };
}
