# lib/checks/network-invariants.nix - the promises the network makes, checked against the evaluated
# fleet instead of against a convention.
#
# Every invariant here was a real failure at some point, which is why it is a check and not a comment:
# a carried zone without a forward rule (the packets stop at the delivery host), a name that resolves to
# an address nothing routes, a client that routes a home zone it has no business routing, a resolver
# list naming a host that is not ours. The check returns its violations and the flake turns an empty
# list into a passing build - a check that cannot fail loudly is not a check.
{
  lib,
  self,
  hostNames,
}:
let
  cfgOf = name: self.nixosConfigurations.${name}.config;

  # The inventory is the same on every host; read it from one of them.
  reference = cfgOf (builtins.head hostNames);
  topology = reference.my.topology;
  subnets = topology.subnets;

  meshCidr = subnets.mesh.cidr;
  lanZones = topology.lanZones;
  carriedZones = topology.announcedZones;
  carriedCidrs = map (zone: subnets.${zone}.cidr) carriedZones;

  lanRouter = topology.lanRouter;
  homeDoor = topology.hosts.${lanRouter}.ipv4;
  meshDoors = map (name: topology.hosts.${name}.wireguardIpv4) (
    lib.filter (name: topology.hosts ? ${name}) topology.resolverHosts
  );
  ingress = topology.hosts.${topology.ingressHost}.ipv4;

  # A host may be declared in the inventory without being a deploy target (the router and the access
  # point are), so the checks run over the configurations that actually exist.
  deployed = lib.filter (name: topology.hosts ? ${name}) hostNames;

  # 1. The host that carries the home zones into the mesh is the one that forwards mesh traffic into
  #    them - and it does so exactly when it carries something.
  forwards =
    name: lib.hasInfix "ip saddr ${meshCidr} accept" (cfgOf name).networking.firewall.extraForwardRules;
  carries = carriedZones != [ ];
  forwardViolations =
    lib.optional (
      forwards lanRouter != carries
    ) "forward: ${lanRouter} forwards=${toString (forwards lanRouter)} but carries=${toString carries}"
    ++ lib.concatMap (
      name:
      lib.optional (
        name != lanRouter && forwards name
      ) "forward: ${name} forwards mesh traffic into the home LAN although it carries no zone"
    ) deployed;

  # 2. A host inside the home LAN installs no route for a carried zone - it reaches it through its own
  #    gateway - and a node that is not inside carries all of them, because abroad it has no other path.
  inLan =
    name:
    let
      host = topology.hosts.${name};
    in
    host.ipv4 != null && builtins.elem host.zone lanZones;
  tunnelCidrs =
    name: lib.concatMap (peer: peer.allowedIPs) (cfgOf name).networking.wireguard.interfaces.wg0.peers;
  routeViolations = lib.concatMap (
    name:
    let
      routes = tunnelCidrs name;
    in
    if inLan name then
      map (cidr: "route: ${name} is inside the home LAN and still routes ${cidr} into its tunnel") (
        lib.filter (cidr: builtins.elem cidr routes) carriedCidrs
      )
    else
      map (cidr: "route: ${name} is not inside the home LAN and does not carry ${cidr}") (
        lib.filter (cidr: !builtins.elem cidr routes) carriedCidrs
      )
  ) deployed;

  # 3. The doors follow the class: a host fixed at home has the home door alone - a mesh door would be a
  #    liability, because a single failed probe would move its LAN lookups onto the overlay plane. A node
  #    that is not fixed at home has the home door first, so a node inside the LAN uses the LAN, and then
  #    every declared resolver's overlay address, which is what makes the resolver survive a home outage.
  doorViolations = lib.concatMap (
    name:
    let
      host = topology.hosts.${name};
      actual = (cfgOf name).networking.nameservers;
      sorted = lib.sort (a: b: a < b);
      inHomeZone = builtins.elem host.zone lanZones;
      ok =
        if !inHomeZone then
          sorted actual == sorted meshDoors
        else if host.ipv4 == null then
          (actual != [ ] && builtins.head actual == homeDoor)
          && sorted actual == sorted ([ homeDoor ] ++ meshDoors)
        else
          actual == [ homeDoor ];
    in
    lib.optional (!ok) (
      "doors: ${name} resolves through ${builtins.toJSON actual}, expected ${
        if inHomeZone then "the home door first, then the mesh doors" else "the mesh doors"
      }"
    )
  ) deployed;

  # 3b. A declared resolver has to be one: a door nobody serves is worse than no door, because the
  #     clients are told to use it.
  resolverHostViolations = lib.concatMap (
    name:
    if !(topology.hosts ? ${name}) then
      [ "resolvers: ${name} is declared as a resolver but is not a host of the inventory" ]
    else if !(builtins.elem name hostNames) then
      [ "resolvers: ${name} is declared as a resolver but is not a deploy target" ]
    else if !(cfgOf name).my.features.services.dns.enable then
      [ "resolvers: ${name} is declared as a resolver but does not run one" ]
    else if topology.hosts.${name}.wireguardIpv4 == null then
      [ "resolvers: ${name} is declared as a resolver but has no overlay address to serve on" ]
    else
      [ ]
  ) topology.resolverHosts;

  # 4. Every resolver the inventory hands out belongs to a host of this fleet. One that knows none of
  #    our names would resolve the internet and fail silently on everything internal.
  fleetAddresses = lib.concatMap (
    name:
    let
      host = topology.hosts.${name};
    in
    lib.optional (host.ipv4 != null) host.ipv4
    ++ lib.optional (host.wireguardIpv4 != null) host.wireguardIpv4
  ) (lib.attrNames topology.hosts);
  resolverViolations = map (
    address: "resolvers: ${address} is handed to clients but belongs to no host in the inventory"
  ) (lib.filter (address: !builtins.elem address fleetAddresses) topology.resolvers);

  # 5. A rendered client routes the mesh and the ingress, and no home zone: a phone reaches the devices
  #    of the house while it is in the house, not through the relays.
  clientViolations = lib.concatMap (
    name:
    let
      clients = (cfgOf name).my.features.system.networking.wireguard.clientConfigs;
      allowedIPsOf =
        client:
        lib.concatStrings (
          lib.filter (line: lib.hasPrefix "AllowedIPs" line) (
            lib.splitString "\n" (cfgOf name).sops.templates."wg-${client}.conf".content
          )
        );
    in
    lib.concatMap (
      client:
      let
        line = allowedIPsOf client;
      in
      map (cidr: "client ${client} (rendered on ${name}) routes the home zone ${cidr}") (
        lib.filter (cidr: lib.hasInfix cidr line) carriedCidrs
      )
      ++ lib.optional (
        !(lib.hasInfix meshCidr line)
      ) "client ${client} (rendered on ${name}) does not route the mesh"
      ++
        lib.optional (ingress != null && !(lib.hasInfix ingress line))
          "client ${client} (rendered on ${name}) does not route the ingress ${ingress}, so the resolver's public door is unreachable inside the tunnel"
    ) clients
  ) deployed;

  # 6. A device has one address and no overlay identity, so its name may only be answered off the LAN
  #    when its zone is carried - otherwise the answer would name an address nothing routes.
  resolverHost = lib.findFirst (name: (cfgOf name).my.features.services.dns.enable) null deployed;
  strip = name: lib.removeSuffix "." name;
  deviceViolations =
    if resolverHost == null then
      [ "answers: no host in the fleet runs the resolver" ]
    else
      let
        answers = (cfgOf resolverHost).my.features.services.dns.answers;
        answered =
          name: plane: lib.any (answer: strip answer.name == strip name && answer.plane == plane) answers;
      in
      lib.concatMap (
        devName:
        let
          device = topology.devices.${devName};
          fqdn = reference.my.contracts.projections.deviceFqdnOf.${devName};
          shouldAnswer = builtins.elem device.zone carriedZones;
        in
        lib.optional (answered fqdn "overlay" != shouldAnswer)
          "answers: ${fqdn} is answered off the LAN = ${toString (answered fqdn "overlay")}, but its zone '${device.zone}' is carried = ${toString shouldAnswer}"
        ++ lib.optional (!(answered fqdn "lan")) "answers: ${fqdn} is not answered in the LAN plane"
      ) (lib.attrNames topology.devices);
in
{
  invariants = [
    "the LAN router forwards mesh traffic exactly when it carries a zone"
    "a host inside the home LAN installs no route for a carried zone; a node outside carries all of them"
    "the resolver doors follow the host class, derived from the zone"
    "every declared resolver runs one, and can be reached where it is announced"
    "every resolver handed to clients belongs to a host of this fleet"
    "a rendered client routes the mesh and the ingress, and no home zone"
    "a device name is answered off the LAN exactly when its zone is carried"
  ];
  violations =
    forwardViolations
    ++ routeViolations
    ++ doorViolations
    ++ resolverHostViolations
    ++ resolverViolations
    ++ clientViolations
    ++ deviceViolations;
}
