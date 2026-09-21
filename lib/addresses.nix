# lib/addresses.nix - the one place that decides which address a fleet-internal consumer uses.
#
# A host has up to two addresses: the one in its zone and the one on the mesh. Which of them a service
# should *use* is a property of the pair, not of the host - and it used to be decided in five modules, in
# five slightly different ways (measured 2026-09-21: caddy preferred the overlay, blocky the LAN address,
# prometheus always the overlay).
#
# The rule: when both sides are in a home zone, the LAN address is used, because then the traffic stays
# in the house. Everything else takes the overlay address, because a cloud host cannot reach a home zone
# at all - the mesh carries the overlay and the zones that need it, not the LAN.
#
# A host is "at home" when it has a fixed address in one of `my.topology.lanZones`. A roaming node is
# therefore not treated as being at home, which is what keeps a service on a notebook from being told to
# use a LAN address it does not always have.
# The rule is pure Nix and needs nothing from the module system, so it ignores whatever a caller passes
# to it: a file that demands an argument it never uses is a lie about its dependencies.
_: rec {
  isAtHome =
    topology: host:
    host != null && host.ipv4 != null && builtins.elem (host.zone or "") topology.lanZones;

  # The address a service on `consumer` uses to reach `peer`.
  serviceAddress =
    {
      topology,
      consumer,
      peer,
    }:
    if peer == null then
      null
    else if isAtHome topology consumer && isAtHome topology peer then
      peer.ipv4
    else if peer.wireguardIpv4 != null then
      peer.wireguardIpv4
    else
      peer.ipv4;
}
