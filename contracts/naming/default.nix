# contracts/naming/default.nix
# Normative naming invariants (NAMING.md §7).
#
# These assertions make the naming rules of ARCHITECTURE.md §1/§3/§8.1 *enforceable*.
# Without them the drift documented in NAMING.md §0.2 could reappear silently: nothing
# failed when a service name encoded a host, when a public service sat on an unreachable
# host, or when an unauthenticated endpoint was published.
#
# Every host evaluates the same fleet-wide projection, so `nix flake check` (via the
# eval-hosts check) fails for the whole cluster as soon as one rule is violated.
{
  config,
  lib,
  ...
}:

let
  topology = config.my.topology;

  flakeConfigurations =
    config._module.specialArgs.flake.nixosConfigurations or {
      "${config.networking.hostName}" = config;
    };

  # Every declared endpoint of the whole fleet, flattened.
  endpoints = lib.concatLists (
    lib.mapAttrsToList (
      hostName: hostConfig:
      lib.concatLists (
        lib.mapAttrsToList (
          svcName: contract:
          lib.mapAttrsToList (epName: ep: {
            inherit
              hostName
              svcName
              epName
              ep
              ;
          }) contract.endpoints
        ) (hostConfig.config.my.contracts.provides or { })
      )
    ) flakeConfigurations
  );

  # Only endpoints that claim a name participate in the naming invariants.
  named = builtins.filter (e: e.ep.canonicalDomain != null) endpoints;

  fqdns = map (e: e.ep.canonicalDomain) named;

  label = e: "${e.hostName}:${e.svcName}.${e.epName}";

  duplicatesOf =
    values: lib.unique (lib.filter (v: builtins.length (lib.filter (x: x == v) values) > 1) values);

  # I1 - each host contributes exactly one node FQDN; hostnames are unique by construction,
  #      so the meaningful check is that no two hosts claim the same overlay address.
  wireguardAddresses = lib.filter (a: a != null) (
    map (h: h.wireguardIpv4) (lib.attrValues topology.hosts)
  );
  duplicateWireguard = duplicatesOf wireguardAddresses;

  # I2 - one name, one owner, fleet-wide.
  duplicateFqdns = duplicatesOf fqdns;

  aliasNames = lib.concatMap (e: e.ep.extraDomains ++ e.ep.aliases) named;

  # Aliases that collide with a canonical name owned by another endpoint.
  collidingWith = universe: candidates: builtins.filter (c: builtins.elem c universe) candidates;
  aliasCollisions = duplicatesOf (collidingWith fqdns aliasNames);

  # I3 - a `public` endpoint must be reachable from the ingress. That means the provider has
  #      an address the ingress can dial (LAN address or overlay address); it does *not* mean
  #      the provider has a public address (NAMING.md §3.1).
  unreachablePublic = builtins.filter (
    e:
    e.ep.scope == "public"
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
    e.ep.fqdn != null
    && (
      lib.hasInfix ".lan." e.ep.fqdn || lib.hasInfix ".vpn." e.ep.fqdn || lib.hasInfix ".iot." e.ep.fqdn
    )
  ) named;

  # I9 - publishing an unauthenticated service is a decision, not a default.
  unauthenticatedPublic = builtins.filter (
    e: e.ep.scope == "public" && e.ep.auth == "none" && e.ep.publicExempt == null
  ) named;

  report =
    title: items:
    "${title}: "
    + lib.concatStringsSep ", " (map (e: if builtins.isString e then e else label e) items);
in
{
  options.my.contracts.projections = lib.mkOption {
    type = lib.types.submodule {
      options = {
        fqdns = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          description = "Every service FQDN derived from the contract fleet.";
        };
        hostFqdns = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          description = "Every host FQDN of the `node` plane (ARCHITECTURE.md §3.3).";
        };
        aliases = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          description = "Deprecation report: legacy names still published as aliases (I8).";
        };
      };
    };
    readOnly = true;
    description = "Read-only naming projections, derived from topology and contracts.";
  };

  config = {
    my.contracts.projections = {
      fqdns = lib.unique fqdns;
      hostFqdns = map (hostName: "${hostName}.node.${topology.domain}") (lib.attrNames topology.hosts);
      aliases = lib.unique aliasNames;
    };

    assertions = [
      {
        assertion = duplicateWireguard == [ ];
        message = report "Naming I1: hosts share a WireGuard address" duplicateWireguard;
      }
      {
        assertion = duplicateFqdns == [ ];
        message = report "Naming I2: endpoints derive the same FQDN" duplicateFqdns;
      }
      {
        assertion = aliasCollisions == [ ];
        message = report "Naming I2: an alias collides with a canonical FQDN" aliasCollisions;
      }
      {
        assertion = unreachablePublic == [ ];
        message = report "Naming I3: public endpoint on a host the ingress cannot reach" unreachablePublic;
      }
      {
        assertion = internalPlaneOverrides == [ ];
        message = report "Naming I4: explicit fqdn inside an internal plane" internalPlaneOverrides;
      }
      {
        assertion = unauthenticatedPublic == [ ];
        message = report "Naming I9: public endpoint with auth = \"none\" and no publicExempt reason" unauthenticatedPublic;
      }
    ];
  };
}
