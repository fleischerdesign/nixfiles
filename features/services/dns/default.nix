# features/services/dns/default.nix - Knot Resolver 6 with plane-correct views
#
# One resolver answers three planes, selected by the *source address* of the query:
#
#   lan      a client on a home zone        -> the LAN address (the packet stays local)
#   overlay  a client on the mesh           -> the overlay address (reachable over wg0)
#   public   a client anywhere else         -> the ingress (services) / overlay (nodes)
#
# A name has one address per plane and the plane is a property of where the question came
# from, not of the answer. See docs/architecture.md 5.2. Every record is a projection of
# `my.topology`, the naming contract and the endpoint contracts - nothing is restated.
#
# This module is deliberately *not* enabled anywhere yet: replacing the live resolver is a
# staged, measured migration (docs/operations.md), not a side effect of adding the module.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.features.services.dns;
  topology = config.my.topology;

  flakeConfigurations =
    config._module.specialArgs.flake.nixosConfigurations or {
      "${config.networking.hostName}" = config;
    };

  ingressHost = topology.hosts.${topology.ingressHost} or null;
  ingressAddress = if ingressHost != null then ingressHost.ipv4 else null;

  # The resolver answers on its own addresses. They are read from the inventory, so a host
  # never restates them; the option below only adds or overrides.
  ownHost = topology.hosts.${config.networking.hostName} or null;
  derivedListen =
    lib.optionalAttrs (ownHost != null && ownHost.ipv4 != null) { lan = ownHost.ipv4; }
    // lib.optionalAttrs (ownHost != null && ownHost.wireguardIpv4 != null) {
      overlay = ownHost.wireguardIpv4;
    };
  effectiveListen = cfg.listenAddresses // derivedListen;

  # Planes. The mesh subnets are the overlay; the remaining trusted zones are the LAN. The
  # guest zone is not a plane of ours: a guest client falls through to the public view.
  overlayCidrs = lib.mapAttrsToList (_: subnet: subnet.cidr) (
    lib.filterAttrs (_: subnet: subnet.trustLevel == "mesh") topology.subnets
  );
  lanCidrs = lib.mapAttrsToList (_: subnet: subnet.cidr) (
    lib.filterAttrs (
      _: subnet: subnet.trustLevel != "mesh" && subnet.trustLevel != "guest"
    ) topology.subnets
  );

  # An address is a LAN address when it is on a private home subnet. A cloud host's `ipv4`
  # is its public address and must never be handed to a LAN client.
  isLanAddress =
    address: address != null && (lib.hasPrefix "10.10." address || lib.hasPrefix "192.168." address);

  # The address of a node in the LAN plane: its own LAN address if it has one, otherwise
  # the overlay - a home client reaches a cloud node through its LAN gateway.
  lanPlaneAddress =
    host:
    if host == null then
      null
    else if isLanAddress host.ipv4 then
      host.ipv4
    else
      host.wireguardIpv4;
  overlayAddress = host: if host == null then null else host.wireguardIpv4;

  # One rule per (name, plane). `records` (zonefile form) is used rather than `address`:
  # an `address` mapping also synthesises a reverse PTR for that address, and every public
  # endpoint resolves to the ingress, so the aggregated PTR exceeded Knot's 512 B record
  # limit and the policy loader refused to start (measured 2026-09-21). Names containing a
  # wildcard are skipped: `local-data` does not expand wildcards, and such names are minted
  # at runtime and resolve upstream.
  mkRules =
    names: addresses:
    lib.flatten (
      lib.map (
        name:
        let
          fqdn = if lib.hasSuffix "." name then name else "${name}.";
        in
        lib.optional (!(lib.hasInfix "*" name)) (
          lib.mapAttrsToList (plane: address: {
            records = "${fqdn} 60 IN A ${address}";
            tags = [ plane ];
          }) (lib.filterAttrs (_: address: address != null) addresses)
        )
      ) names
    );

  nodeRules = lib.concatLists (
    lib.mapAttrsToList (
      hostName: fqdn:
      let
        host = topology.hosts.${hostName};
      in
      mkRules [ fqdn ] {
        lan = lanPlaneAddress host;
        overlay = overlayAddress host;
        public = overlayAddress host;
      }
    ) config.my.contracts.projections.hostFqdnOf
  );

  # A device has no overlay identity: it exists in the LAN plane only. Reaching it from
  # elsewhere is not a name problem - such a device must be *published* as a service.
  deviceRules = lib.concatLists (
    lib.mapAttrsToList (
      devName: fqdn:
      mkRules [ fqdn ] {
        lan = topology.devices.${devName}.ipv4;
      }
    ) config.my.contracts.projections.deviceFqdnOf
  );

  # A service is named once; the plane decides which address terminates it. In the LAN
  # plane it is the serving host; in the public plane it is the ingress, the only
  # component that terminates public TLS.
  serviceRules = lib.concatLists (
    lib.mapAttrsToList (
      hostName: hostConfig:
      let
        host = topology.hosts.${hostName} or null;
      in
      lib.concatLists (
        lib.mapAttrsToList (
          _svcName: contract:
          lib.concatMap (
            ep:
            mkRules (lib.optionals (ep.canonicalDomain != null) [ ep.canonicalDomain ] ++ ep.extraDomains) {
              lan = lanPlaneAddress host;
              overlay = overlayAddress host;
              public = if ep.scope == "public" then ingressAddress else null;
            }
          ) (lib.attrValues contract.endpoints)
        ) (hostConfig.config.my.contracts.provides or { })
      )
    ) flakeConfigurations
  );

  # Blocklist state. Knot reads /etc/hosts-format files directly, so the upstream list is
  # used as-is and blocked names answer 0.0.0.0 - the previous resolver's `zeroIp`.
  blocklistDir = "/var/lib/knot-resolver";
  blocklistEntries = map (url: {
    inherit url;
    host = lib.head (
      lib.splitString "/" (lib.removePrefix "https://" (lib.removePrefix "http://" url))
    );
  }) cfg.blocklists;
in
{
  options.my.features.services.dns = {
    enable = lib.mkEnableOption "Knot Resolver 6 as the fleet resolver (plane-correct views)";

    port = lib.mkOption {
      type = lib.types.port;
      default = 53;
      description = ''
        TCP/UDP port for plain DNS. Staging runs the resolver on a different port so the
        generated configuration can be proven against real names before the live resolver
        is replaced.
      '';
    };

    listenAddresses = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        lan = "10.10.10.10";
        overlay = "10.10.100.10";
      };
      description = ''
        Addresses the resolver answers plain DNS on, keyed by plane name. The plane of an
        answer is decided by the query's source, so the keys are documentation rather than
        behaviour; encrypted transports are added once the resolver's certificate exists.
      '';
    };

    blocklists = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts" ];
      description = ''
        Hosts-format blocklists, fetched on a timer into the resolver's state directory. A
        blocked name resolves to 0.0.0.0.
      '';
    };

    blocklistRefresh = lib.mkOption {
      type = lib.types.str;
      default = "daily";
      description = "systemd calendar expression for the blocklist refresh timer.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = effectiveListen != { };
        message = "DNS: no listen address (the host has neither an `ipv4` nor a `wireguardIpv4` in the topology); the resolver would only answer on localhost.";
      }
    ];

    # The hosts resolve through `my.topology.resolvers` (the resolver's own zone address),
    # not through 127.0.0.1: the resolver binds the zone addresses, so pointing resolv.conf
    # at localhost would ask an address nothing listens on.
    networking.resolvconf.useLocalResolver = lib.mkForce false;

    services.knot-resolver = {
      enable = true;
      settings = {
        network.listen = lib.mapAttrsToList (_: address: {
          interface = address;
          port = cfg.port;
          kind = "dns";
        }) effectiveListen;

        views = [
          {
            subnets = lanCidrs;
            tags = [ "lan" ];
          }
          {
            subnets = overlayCidrs;
            tags = [ "overlay" ];
          }
          {
            # Fallback: everything that is neither on a home zone nor on the mesh. It must
            # exist and be last, because a client matching no view carries no tags and
            # would then see no local records at all.
            subnets = [
              "0.0.0.0/0"
              "::/0"
            ];
            tags = [ "public" ];
          }
        ];

        local-data = {
          rules = nodeRules ++ deviceRules ++ serviceRules;
          addresses-files = lib.optionals (cfg.blocklists != [ ]) [
            "${blocklistDir}/blocklist.hosts"
          ];
        };
      };
    };

    # The blocklist file must exist before the resolver starts - an empty list is valid.
    systemd.tmpfiles.rules = lib.optionals (cfg.blocklists != [ ]) [
      "d ${blocklistDir} 0770 knot-resolver knot-resolver -"
      "f ${blocklistDir}/blocklist.hosts 0660 knot-resolver knot-resolver -"
    ];

    systemd.services.knot-blocklist = lib.mkIf (cfg.blocklists != [ ]) {
      description = "Refresh the resolver's hosts-format blocklists and reload it";
      after = [
        "network-online.target"
        "knot-resolver.service"
      ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        StateDirectory = "knot-resolver";
        RuntimeDirectory = "knot-resolver";
      };
      # The name is resolved through a resolver from the inventory explicitly: the host's
      # own resolv.conf is DHCP-managed and lists the uplink router first, which is not
      # reachable from the zone addresses, so a plain curl would spend its whole timeout
      # failing (measured 2026-09-21). `--resolve` then pins that address for the transfer.
      script = ''
        set -eu
        resolver="${lib.head topology.resolvers}"
        tmp="$(mktemp)"
        : > "$tmp"
        ${lib.concatMapStrings ({ url, host }: ''
          ip="$(${pkgs.bind.dnsutils}/bin/host -W 5 -t A '${host}' "$resolver" | ${pkgs.gawk}/bin/awk '/has address/ { print $4; exit }')"
          ${pkgs.curl}/bin/curl --fail --silent --show-error --location --resolve "${host}:443:$ip" '${url}' >> "$tmp"
          printf '\n' >> "$tmp"
        '') blocklistEntries}
        install -m 0660 -o knot-resolver -g knot-resolver "$tmp" "${blocklistDir}/blocklist.hosts"
        rm -f "$tmp"
        systemctl reload knot-resolver.service
      '';
    };

    systemd.timers.knot-blocklist = lib.mkIf (cfg.blocklists != [ ]) {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.blocklistRefresh;
        Persistent = true;
      };
    };

    my.contracts.provides.dns = {
      endpoints.dns = {
        port = cfg.port;
        protocol = "both";
        scope = "internal";
        directAccess = {
          enable = true;
          protocol = "both";
          interface = "all";
        };
        monitoring.http.enable = false;
      };
    };
  };
}
