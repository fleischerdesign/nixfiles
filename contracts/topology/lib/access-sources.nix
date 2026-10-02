# contracts/topology/lib/access-sources.nix - which addresses carry which trust level.
#
# Backend-independent by construction: it reads the topology and returns addresses, and says nothing
# about how a firewall spells a match. It lives with the topology contract because the translation from
# levels to addresses is a fact about the inventory, not about nftables - which is why a policy check
# can import this without importing a renderer.
{ lib }:
rec {
  # The addresses of the given trust levels, flattened and unique - the one translation from the
  # lattice to addresses, so a policy is written in levels and rendered once.
  sourcesOfTrust =
    topology: levels:
    lib.unique (lib.concatMap (level: topology.sourcesByTrust.${level} or [ ]) levels);

  sourcesOfHosts =
    topology: names:
    lib.unique (
      lib.concatMap (
        name:
        let
          host = topology.hosts.${name};
        in
        lib.filter (address: address != null) [
          host.wireguardIpv4
          host.wireguardIpv6
        ]
      ) names
    );
}
