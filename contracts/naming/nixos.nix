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

  # I1 - a node answers under one name. Hosts and devices are declared in two inventories but project
  #      into the same `node` plane, so a name that appears in both is two machines claiming one record.
  duplicateNodeNames = duplicatesOf (
    lib.attrNames topology.hosts ++ lib.attrNames (topology.devices or { })
  );

  # I2 - one name, one owner, fleet-wide. A canonical name, an `extraDomain` and an `alias` are the same
  #      kind of fact - a name this fleet answers - so they compete for one namespace and are judged
  #      together, per owner. The previous shape compared aliases against canonical names as plain
  #      strings, which missed three real cases: an alias that met another endpoint's canonical name
  #      (one occurrence in the alias list), an alias colliding with an alias, and an `extraDomain` that
  #      duplicated a name. A name an endpoint repeats for itself is not a collision: it has one owner.
  claimedNames = lib.concatMap (
    e:
    map (name: {
      inherit name;
      owner = label e;
    }) ([ e.ep.canonicalDomain ] ++ e.ep.extraDomains ++ e.ep.aliases)
  ) named;

  ownersOfName =
    name: lib.unique (map (claim: claim.owner) (lib.filter (claim: claim.name == name) claimedNames));

  nameCollisions = map (name: "${name} (${lib.concatStringsSep ", " (ownersOfName name)})") (
    lib.unique (
      lib.filter (name: builtins.length (ownersOfName name) > 1) (map (c: c.name) claimedNames)
    )
  );

  # The alias names as a projection; the enforcement above reads `claimedNames`, not this list.
  aliasNames = lib.concatMap (e: e.ep.extraDomains ++ e.ep.aliases) named;

  # I3 - a `public` endpoint must be reachable from the ingress. That means the provider has
  #      an address the ingress can dial (LAN address or overlay address); it does *not* mean
  #      the provider has a public address (docs/naming.md §3.1).
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
      lib.hasInfix ".lan." e.ep.fqdn || lib.hasInfix ".mesh." e.ep.fqdn || lib.hasInfix ".iot." e.ep.fqdn
    )
  ) named;

  # I6 - an explicit fqdn override must stay inside the managed zone. The Cloudflare engine can
  # only manage the apex zone: a foreign domain is sent as a *relative* name and silently
  # created as <domain>.<zone> (observed live: `fleischer.design` became
  # `fleischer.design.vyrx.de`). Foreign zones are served by Caddy and resolved elsewhere.
  outOfZoneOverrides = builtins.filter (
    e:
    e.ep.fqdn != null
    && !(e.ep.fqdn == topology.domain || lib.hasSuffix ".${topology.domain}" e.ep.fqdn)
  ) named;

  # I10 - the ingress terminates TLS and proxies to a remote public endpoint *directly over the
  # mesh* (docs/architecture.md §7.1, "WireGuard-Upstreams"), so such an endpoint must be declared
  # reachable there: listen on a non-loopback address and open the port on the wireguard
  # interface. Without this the ingress answers 502 (observed live for cache.vyrx.de while
  # atticd still bound 127.0.0.1).
  ingressUnreachable = builtins.filter (
    e:
    e.ep.scope == "public"
    && e.hostName != topology.ingressHost
    && !(
      e.ep.directAccess.enable
      && (e.ep.directAccess.interface == "wireguard" || e.ep.directAccess.interface == "all")
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
          description = "Every host FQDN of the `node` plane (docs/architecture.md §3.3).";
        };
        hostFqdnOf = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          description = ''
            Host name -> FQDN of the `node` plane. A mapping so consumers do not have to pair two
            lists by position, which is how a naming scheme drifts.
          '';
        };
        deviceFqdnOf = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          description = "Device name -> FQDN of the `node` plane (microcontrollers are nodes too).";
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
        message = "Naming I2: two endpoints claim the same name: ${lib.concatStringsSep "; " nameCollisions}";
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
        assertion = outOfZoneOverrides == [ ];
        message = report "Naming I6: explicit fqdn outside the managed zone" outOfZoneOverrides;
      }
      {
        assertion = ingressUnreachable == [ ];
        message = report "Naming I10: public endpoint on a remote host that the ingress cannot reach" ingressUnreachable;
      }
      {
        assertion = unauthenticatedPublic == [ ];
        message = report "Naming I9: public endpoint with auth = \"none\" and no publicExempt reason" unauthenticatedPublic;
      }
    ];
  };
}
