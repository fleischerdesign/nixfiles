# apps/lib/fleet.nix - the fleet as audit input, stated once.
#
# Both audits ask the same inventory the same questions - which hosts are deployed, which address a
# host is reached at, what the topology says - so the projection lives here instead of in two copies
# that could disagree about who the fleet is.
{
  lib,
  hostNames,
  self,
}:
let
  cfgOf = name: self.nixosConfigurations.${name}.config;

  # The inventory is the same on every host; read it from one of them.
  reference = cfgOf (builtins.head hostNames);
  topology = reference.my.topology;

  # A host may be declared in the inventory without being a deploy target (the router and the access
  # point are), so the audits run over the configurations that actually exist.
  deployed = lib.filter (name: topology.hosts ? ${name}) hostNames;
  addressOf =
    name:
    if topology.hosts.${name}.wireguardIpv4 != null then
      topology.hosts.${name}.wireguardIpv4
    else
      topology.hosts.${name}.ipv4;
in
{
  inherit
    cfgOf
    topology
    deployed
    addressOf
    ;
}
