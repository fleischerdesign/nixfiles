# lib/checks/network-invariants.nix - the promises the network makes, checked against the evaluated
# fleet instead of against a convention.
#
# Every invariant here was a real failure at some point, which is why it is a check and not a comment:
# a carried zone without a forward rule (the packets stop at the delivery host), a *blanket* forward
# rule (every member reached every device on every port), a name that resolves to an address nothing
# routes, a client that routes a zone it has no business routing, a resolver list naming a host that is
# not ours - and a firewall policy written as shell commands, which is the one that took the network down
# twice. The check returns its violations and the flake turns an empty list into a passing build - a check
# that cannot fail loudly is not a check.
{
  lib,
  self,
  hostNames,
}:
let
  cfgOf = name: self.nixosConfigurations.${name}.config;
  nft = import ../nftables.nix { inherit lib; };

  # The inventory is the same on every host; read it from one of them.
  reference = cfgOf (builtins.head hostNames);
  topology = reference.my.topology;
  subnets = topology.subnets;

  meshCidr = subnets.mesh.cidr;
  lanZones = topology.lanZones;
  carriedZones = topology.announcedZones;
  carriedCidrs = map (zone: subnets.${zone}.cidr) carriedZones;
  hostZoneCidrs = map (zone: subnets.${zone}.cidr) (
    lib.filter (zone: !(builtins.elem zone carriedZones)) lanZones
  );

  lanRouter = topology.lanRouter;
  homeDoor = topology.hosts.${lanRouter}.ipv4;
  meshDoors = map (name: topology.hosts.${name}.wireguardIpv4) (
    lib.filter (name: topology.hosts ? ${name}) topology.resolverHosts
  );
  ingress = topology.hosts.${topology.ingressHost}.ipv4;

  # A host may be declared in the inventory without being a deploy target (the router and the access
  # point are), so the checks run over the configurations that actually exist.
  deployed = lib.filter (name: topology.hosts ? ${name}) hostNames;

  # Every declared endpoint of every device the mesh carries, flattened: the list the device policy is
  # built from, and therefore the list the check has to hold the LAN router to.
  carriedDevices = lib.filterAttrs (
    _: device: builtins.elem device.zone carriedZones
  ) topology.devices;
  declaredEndpoints = lib.concatLists (
    lib.mapAttrsToList (
      deviceName: device:
      lib.mapAttrsToList (endpointName: endpoint: {
        inherit
          deviceName
          endpointName
          device
          endpoint
          ;
      }) device.endpoints
    ) carriedDevices
  );

  # 1. One firewall, rendered. The implementation is nftables, forwarded traffic is filtered (without it
  #    the forward chain accepts by default and every allow-list is decoration), and every permission is a
  #    rule in the firewall's own options. A host that writes a shell command into `extraCommands` fails
  #    this check: that shape is what took the network down twice - it is not validated before it runs, it
  #    is not rebuilt atomically, and a rule whose declaration is withdrawn never leaves the chain.
  inputRules = name: (cfgOf name).networking.firewall.extraInputRules;
  forwardRules = name: (cfgOf name).networking.firewall.extraForwardRules;
  firewallViolations = lib.concatMap (
    name:
    lib.optional (
      !(cfgOf name).networking.nftables.enable
    ) "firewall: ${name} does not use the nftables implementation"
    ++ lib.optional (
      !(cfgOf name).networking.firewall.filterForward
    ) "firewall: ${name} does not filter forwarded traffic, so its forward chain accepts by default"
    ++ lib.optional (
      (cfgOf name).networking.firewall.extraCommands != ""
    ) "firewall: ${name} still writes shell commands into extraCommands"
    ++ lib.optional (lib.hasInfix "iptables" (
      inputRules name + forwardRules name
    )) "firewall: ${name} has a generated rule that names a command instead of an nftables match"
  ) deployed;

  # 2. The LAN router forwards what the carried zones' devices declare - and nothing is opened for a
  #    device that declared nothing, because the chain's policy is drop. The audit proves the same thing
  #    from the wire; this proves it from the configuration, including the ports nobody declared.
  deviceForwardViolations = lib.concatMap (
    entry:
    let
      rules = forwardRules lanRouter;
      sources = nft.sourcesOfTrust topology entry.endpoint.from;
      hasSource = lib.any (address: lib.hasInfix address rules) sources;
    in
    lib.optional (
      !(lib.hasInfix "ip daddr ${entry.device.ipv4}" rules)
    ) "forward: ${entry.deviceName} is carried, but ${lanRouter} has no rule for its address"
    ++
      lib.optional (!(lib.hasInfix "dport ${toString entry.endpoint.port}" rules))
        "forward: ${entry.deviceName}.${entry.endpointName} declares port ${toString entry.endpoint.port}, but ${lanRouter} has no rule for it"
    ++
      lib.optional (!hasSource)
        "forward: ${entry.deviceName}.${entry.endpointName} declares a level whose addresses appear in no rule of ${lanRouter}"
  ) declaredEndpoints;

  # 3. Every endpoint that opens a port appears in the input rules, scoped the way it declared itself: the
  #    local network reaching it, and the mesh only for the levels it is for.
  endpointViolations = lib.concatMap (
    name:
    let
      provides = (cfgOf name).my.contracts.provides or { };
      endpoints = lib.concatLists (
        map (contract: lib.attrValues (contract.endpoints or { })) (lib.attrValues provides)
      );
      rules = inputRules name;
    in
    lib.concatMap (
      ep:
      let
        wantsMesh = ep.directAccess.interface == "wireguard" || ep.canonicalDomain != null;
        wantsLocal = ep.directAccess.interface == "all";
      in
      lib.optional (
        !(lib.hasInfix "dport ${toString ep.port}" rules)
      ) "input: ${name} declares an endpoint on port ${toString ep.port} but opens no rule for it"
      ++ lib.optional (
        wantsLocal && !(lib.hasInfix "iifname != \"wg0\"" rules)
      ) "input: ${name} never scopes a rule to the local network (iifname != \"wg0\")"
      ++ lib.optional (
        wantsMesh && !(lib.hasInfix "iifname \"wg0\"" rules)
      ) "input: ${name} has an endpoint that the mesh must reach, but no rule names the mesh interface"
    ) (lib.filter (ep: ep.directAccess.enable && ep.directAccess.interface != "local") endpoints)
  ) deployed;

  # 4. A host inside the home LAN installs no route for a carried zone - it reaches it through its own
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

  # 5. The doors follow the class: a host fixed at home has the home door alone - a mesh door would be a
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

  # 5b. A declared resolver has to be one: a door nobody serves is worse than no door, because the
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

  # 6. Every resolver the inventory hands out belongs to a host of this fleet. One that knows none of
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

  # 7. A rendered client routes the mesh, the ingress and every zone the mesh carries - that is what makes
  #    a carried device reachable for a phone that is not at home - and no host zone: a client that routed
  #    `infra` or `corp` would send its traffic through a hub while it sits in the LAN.
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
      contentOf = client: (cfgOf name).sops.templates."wg-${client}.conf".content;
      declaredResolvers = map (resolver: topology.hosts.${resolver}.wireguardIpv4) (
        lib.filter (resolver: topology.hosts.${resolver}.wireguardIpv4 != null) topology.resolverHosts
      );
    in
    lib.concatMap (
      client:
      let
        line = allowedIPsOf client;
      in
      map (
        cidr:
        "client ${client} (rendered on ${name}) does not route the carried zone ${cidr}, so a device in it is unreachable outside the LAN"
      ) (lib.filter (cidr: !(lib.hasInfix cidr line)) carriedCidrs)
      ++
        lib.optional (!(lib.hasInfix "DNS =" (contentOf client)))
          "client ${client} (rendered on ${name}) carries no resolver, so its VPN network cannot resolve the name it is told to use for private DNS"
      ++ lib.concatMap (
        address:
        lib.optional (
          !(lib.hasInfix address (contentOf client))
        ) "client ${client} (rendered on ${name}) does not carry the declared resolver ${address}"
      ) declaredResolvers
      ++ lib.concatMap (
        app:
        lib.optional (!(lib.hasInfix app (contentOf client)))
          "client ${client} (rendered on ${name}) declares '${app}' as excluded from the tunnel, but the profile does not carry it"
      ) (topology.hosts.${client}.excludedApplications or [ ])
      ++ lib.optional (
        !(lib.hasInfix meshCidr line)
      ) "client ${client} (rendered on ${name}) does not route the mesh"
      ++
        lib.optional (ingress != null && !(lib.hasInfix ingress line))
          "client ${client} (rendered on ${name}) does not route the ingress ${ingress}, so the resolver's public door is unreachable inside the tunnel"
      ++ map (
        cidr: "client ${client} (rendered on ${name}) routes the host zone ${cidr}, which it does not need"
      ) (lib.filter (cidr: lib.hasInfix cidr line) hostZoneCidrs)
    ) clients
  ) deployed;

  # 8. A device has one address and no overlay identity, so its name may only be answered off the LAN when
  #    its zone is carried - otherwise the answer would name an address nothing routes. Both off-LAN planes
  #    follow that rule, because a client that is not in the LAN reaches the resolver through the mesh door
  #    or the public one, depending on where it is.
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
          "answers: ${fqdn} is answered on the overlay plane = ${toString (answered fqdn "overlay")}, but its zone '${device.zone}' is carried = ${toString shouldAnswer}"
        ++
          lib.optional (answered fqdn "public" != shouldAnswer)
            "answers: ${fqdn} is answered on the public plane = ${toString (answered fqdn "public")}, but its zone '${device.zone}' is carried = ${toString shouldAnswer}"
        ++ lib.optional (!(answered fqdn "lan")) "answers: ${fqdn} is not answered in the LAN plane"
      ) (lib.attrNames topology.devices);

  # 9. A device declaration is only meaningful where the mesh carries the device, and a level that has no
  #    addresses in the inventory cannot be asked from. Both are declarations that look like access and are
  #    none, which is the one kind of mistake a policy derived from data cannot survive quietly.
  declarationViolations = lib.concatMap (
    entry:
    lib.optional (!(builtins.elem entry.device.zone carriedZones))
      "declaration: ${entry.deviceName}.${entry.endpointName} is declared on a device in zone '${entry.device.zone}', which the mesh does not carry"
    ++ map (
      level:
      "declaration: ${entry.deviceName}.${entry.endpointName} allows '${level}', which has no addresses in the inventory"
    ) (lib.filter (level: (topology.sourcesByTrust.${level} or [ ]) == [ ]) entry.endpoint.from)
  ) declaredEndpoints;
in
{
  invariants = [
    "one firewall, rendered: nftables, forwarding filtered, no shell command in the rules"
    "the LAN router opens exactly the ports the carried zones' devices declare"
    "every endpoint that opens a port appears in the input rules, scoped to interface and levels"
    "a host inside the home LAN installs no route for a carried zone; a node outside carries all of them"
    "the resolver doors follow the host class, derived from the zone"
    "every declared resolver runs one, and can be reached where it is announced"
    "every resolver handed to clients belongs to a host of this fleet"
    "a rendered client carries the resolvers, routes the mesh, the ingress and the carried zones, and no host zone"
    "a device name is answered off the LAN exactly when its zone is carried"
    "every device declaration names a carried device and a trust level that exists"
  ];
  violations =
    firewallViolations
    ++ deviceForwardViolations
    ++ endpointViolations
    ++ routeViolations
    ++ doorViolations
    ++ resolverHostViolations
    ++ resolverViolations
    ++ clientViolations
    ++ deviceViolations
    ++ declarationViolations;
}
