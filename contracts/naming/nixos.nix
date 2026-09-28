# contracts/naming/nixos.nix
# Normative naming invariants (docs/naming.md §7).
#
# These assertions make the naming rules of docs/architecture.md §1/§3/§8.1 *enforceable*.
# Without them the drift documented in docs/naming.md §0.2 could reappear silently: nothing
# failed when a service name encoded a host, when a public service sat on an unreachable
# host, or when an unauthenticated endpoint was published.
#
# Every host evaluates the same fleet-wide projection, so `nix flake check` (via the
# eval-hosts check) fails for the whole cluster as soon as one rule is violated.
{
  config,
  lib,
  fleetConfigs,
  ...
}:

let
  topology = config.my.topology;

  # One rule, one place: everything that is a node lives in the host plane, <name>.node.<domain>.
  # Consumers read the mappings, so they never pair two lists by position.
  hostFqdnOf = lib.genAttrs (lib.attrNames topology.hosts) (name: "${name}.node.${topology.domain}");
  deviceFqdnOf = lib.genAttrs (lib.attrNames (topology.devices or { })) (
    name: "${name}.node.${topology.domain}"
  );

  flakeConfigurations = fleetConfigs.systems config;

  # Every declared publication of the whole fleet, with the endpoint it names resolved for the
  # reachability invariants. A name is a publication fact; the listener only carries direct access.
  publications = lib.concatLists (
    lib.mapAttrsToList (
      hostName: hostConfig:
      lib.concatLists (
        lib.mapAttrsToList (
          svcName: contract:
          lib.mapAttrsToList (pubName: pub: {
            inherit
              hostName
              svcName
              pubName
              pub
              ;
            ep = contract.endpoints.${pub.endpoint};
          }) contract.publications
        ) (fleetConfigs.providesOf hostConfig)
      )
    ) flakeConfigurations
  );

  # Only publications that claim a name participate in the naming invariants.
  named = builtins.filter (e: e.pub.canonicalDomain != null) publications;

  fqdns = map (e: e.pub.canonicalDomain) named;

  label = e: "${e.hostName}:${e.svcName}.${e.pubName}";

  duplicatesOf =
    values: lib.unique (lib.filter (v: builtins.length (lib.filter (x: x == v) values) > 1) values);

  # I1 - each host contributes exactly one node FQDN; hostnames are unique by construction,
  #      so the meaningful check is that no two hosts claim the same overlay address.
  wireguardAddresses = lib.filter (a: a != null) (
    map (h: h.wireguardIpv4) (lib.attrValues topology.hosts)
  );
  duplicateWireguard = duplicatesOf wireguardAddresses;

  # I1 - a node answers under one name. Hosts and devices are declared in two inventories but project
  #      into the same `node` plane, so a name that appears in both is two machines claiming one record.
  duplicateNodeNames = duplicatesOf (
    lib.attrNames topology.hosts ++ lib.attrNames (topology.devices or { })
  );

  # I2 - one name, one owner, fleet-wide. A canonical name, an `extraDomain` and an `alias` are the same
  #      kind of fact - a name this fleet answers - so they compete for one namespace and are judged
  #      together, per owner. A name a publication repeats for itself is not a collision: it has one owner.
  nodeClaims = lib.mapAttrsToList (node: fqdn: {
    name = lib.toLower (lib.removeSuffix "." fqdn);
    owner = "node:${node}";
  }) (hostFqdnOf // deviceFqdnOf);

  claimedNames =
    nodeClaims
    ++ lib.concatMap (
      e:
      map (name: {
        name = lib.toLower (lib.removeSuffix "." name);
        owner = label e;
      }) ([ e.pub.canonicalDomain ] ++ e.pub.extraDomains ++ e.pub.aliases)
    ) named;

  ownersOfName =
    name: lib.unique (map (claim: claim.owner) (lib.filter (claim: claim.name == name) claimedNames));

  nameCollisions = map (name: "${name} (${lib.concatStringsSep ", " (ownersOfName name)})") (
    lib.unique (
      lib.filter (name: builtins.length (ownersOfName name) > 1) (map (c: c.name) claimedNames)
    )
  );

  # The alias names as a projection; the enforcement above reads `claimedNames`, not this list.
  aliasNames = lib.concatMap (e: e.pub.extraDomains ++ e.pub.aliases) named;

  # I3 - a `public` publication must be reachable from the ingress. That means the provider has
  #      an address the ingress can dial (LAN address or overlay address); it does *not* mean
  #      the provider has a public address (docs/naming.md §3.1).
  unreachablePublic = builtins.filter (
    e:
    e.pub.scope == "public"
    && (
      let
        host = topology.hosts.${e.hostName} or null;
      in
      host == null || (host.ipv4 == null && host.wireguardIpv4 == null)
    )
  ) named;

  # I4 - internal planes are never published in the public zone. An explicit `fqdn` override
  #      inside an internal plane would leak it.
  internalPlaneOverrides = builtins.filter (
    e:
    e.pub.fqdn != null
    && (
      lib.hasInfix ".lan." e.pub.fqdn
      || lib.hasInfix ".mesh." e.pub.fqdn
      || lib.hasInfix ".iot." e.pub.fqdn
    )
  ) named;

  # I6 - an explicit fqdn override must stay inside the managed zone. The Cloudflare engine can
  # only manage the apex zone: a foreign domain is sent as a *relative* name and silently
  # created as <domain>.<zone> (observed live: `fleischer.design` became
  # `fleischer.design.vyrx.de`). Foreign zones are served by Caddy and resolved elsewhere.
  outOfZoneOverrides = builtins.filter (
    e:
    e.pub.fqdn != null
    && !(e.pub.fqdn == topology.domain || lib.hasSuffix ".${topology.domain}" e.pub.fqdn)
  ) named;

  # I10 - the ingress terminates TLS and proxies to a remote public endpoint *directly over the
  # mesh* (docs/architecture.md §7.1, "WireGuard-Upstreams"), so such an endpoint must be declared
  # reachable there: listen on a non-loopback address and open the port on the wireguard
  # interface. Without this the ingress answers 502 (observed live for cache.vyrx.de while
  # atticd still bound 127.0.0.1).
  ingressUnreachable = builtins.filter (
    e:
    e.pub.scope == "public"
    && e.hostName != topology.ingressHost
    && !(
      e.ep.directAccess.enable
      && (e.ep.directAccess.interface == "wireguard" || e.ep.directAccess.interface == "all")
    )
  ) named;

  # I9 - publishing an unauthenticated service is a decision, not a default.
  unauthenticatedPublic = builtins.filter (
    e: e.pub.scope == "public" && e.pub.auth == "none" && e.pub.publicExempt == null
  ) named;

  report =
    title: items:
    "${title}: "
    + lib.concatStringsSep ", " (map (e: if builtins.isString e then e else label e) items);
in
{
  config = {
    my.contracts.projections = {
      fqdns = lib.unique fqdns;
      inherit hostFqdnOf deviceFqdnOf;
      hostFqdns = lib.attrValues hostFqdnOf;
      aliases = lib.unique aliasNames;
    };

    assertions = [
      {
        assertion = duplicateWireguard == [ ];
        message = report "Naming I1: hosts share a WireGuard address" duplicateWireguard;
      }
      {
        assertion = duplicateNodeNames == [ ];
        message = report "Naming I1: a name is declared as both a host and a device" duplicateNodeNames;
      }
      {
        assertion = nameCollisions == [ ];
        message = "Naming I2: two publications claim the same name: ${lib.concatStringsSep "; " nameCollisions}";
      }
      {
        assertion = unreachablePublic == [ ];
        message = report "Naming I3: public publication on a host the ingress cannot reach" unreachablePublic;
      }
      {
        assertion = internalPlaneOverrides == [ ];
        message = report "Naming I4: explicit fqdn inside an internal plane" internalPlaneOverrides;
      }
      {
        assertion = outOfZoneOverrides == [ ];
        message = report "Naming I6: explicit fqdn outside the managed zone" outOfZoneOverrides;
      }
      {
        assertion = ingressUnreachable == [ ];
        message = report "Naming I10: public publication on a remote host that the ingress cannot reach" ingressUnreachable;
      }
      {
        assertion = unauthenticatedPublic == [ ];
        message = report "Naming I9: public publication with auth = \"none\" and no publicExempt reason" unauthenticatedPublic;
      }
    ];
  };
}
