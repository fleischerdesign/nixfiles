{
  config,
  lib,
  features,
  ...
}:
let
  cfg = config.my.features.services.blocky;
  topology = config.my.topology;

  # Fleet-wide configuration graph (`flake` is injected by lib/core/system-builder.nix).
  flakeConfigurations =
    config._module.specialArgs.flake.nixosConfigurations or {
      "${config.networking.hostName}" = config;
    };

  # Address a LAN client should use to reach a host: the LAN address when the host lives in
  # the home network, otherwise the WireGuard overlay address.
  reachableAddress =
    host:
    if host == null then
      null
    else if
      host.ipv4 != null && (lib.hasPrefix "10.10." host.ipv4 || lib.hasPrefix "192.168." host.ipv4)
    then
      host.ipv4
    else if host.wireguardIpv4 != null then
      host.wireguardIpv4
    else
      host.ipv4;

  # Split-horizon projection (ARCHITECTURE.md §5 and §8.1): every named contract endpoint
  # resolves locally to the host that serves it - the *same* name that resolves publicly to
  # the ingress. The internal planes (.lan/.vpn/.iot) exist only here.
  endpointMappings = lib.listToAttrs (
    lib.concatLists (
      lib.mapAttrsToList (
        hostName: hostConfig:
        let
          address = reachableAddress (topology.hosts.${hostName} or null);
        in
        lib.optionals (address != null) (
          lib.concatLists (
            lib.mapAttrsToList (
              _svcName: contract:
              lib.concatMap (
                ep:
                map (name: {
                  inherit name;
                  value = address;
                }) (lib.optionals (ep.canonicalDomain != null) [ ep.canonicalDomain ] ++ ep.extraDomains)
              ) (lib.attrValues contract.endpoints)
            ) (hostConfig.config.my.contracts.provides or { })
          )
        )
      ) flakeConfigurations
    )
  );
in
{
  options.my.features.services.blocky = {
    enable = lib.mkEnableOption "Blocky DNS Ad-blocker";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (features.requires [ "services.redis" ] config)

      {
        services.blocky = {
          enable = true;
          settings = {
            # Network configuration - Blocky expects the port or address:port
            ports.dns = 53;
            ports.http = 4000; # Port for metrics and API

            # Upstream DNS (using DNS-over-HTTPS for privacy)
            upstream.default = [
              "https://one.one.one.one/dns-query"
              "https://dns.google/dns-query"
            ];

            # Bootstrap DNS — bricht den DNS-Loop (Blocky → System-Resolver → MagicDNS → Blocky)
            # Löst DoH-Upstream-Hostnames via Plain-DNS auf, ohne den System-Resolver zu nutzen
            bootstrapDns = [
              { upstream = "1.1.1.1"; }
              { upstream = "9.9.9.9"; }
            ];

            # Custom DNS Mapping (Split DNS)
            # Subdomains werden automatisch mit aufgelöst (Blocky-Feature)
            # Heimnetz-Hosts: lokale IP (via LAN oder Subnet-Router)
            # Externe Cloud-Hosts: WireGuard-Overlay IP (IPv4 & RFC 4193 ULA IPv6)
            # IoT-Geräte: statische IP aus my.topology.devices
            customDNS = {
              # Names come from the naming engine, which owns the node plane (<name>.node.<domain>).
              # The per-record domain field that used to feed this was a second, contradictory
              # scheme: it called hom-srv-01 "srv.lan.vyrx.de".
              mapping =
                (lib.mapAttrs'
                  (
                    hostName: fqdn:
                    let
                      host = topology.hosts.${hostName};
                      primaryIp =
                        if
                          host.ipv4 != null && (lib.hasPrefix "10.10." host.ipv4 || lib.hasPrefix "192.168." host.ipv4)
                        then
                          host.ipv4
                        else if host.wireguardIpv4 != null then
                          host.wireguardIpv4
                        else
                          host.ipv4;
                      ipv6 = host.wireguardIpv6 or null;
                    in
                    lib.nameValuePair fqdn (if ipv6 != null then "${primaryIp},${ipv6}" else primaryIp)
                  )
                  (
                    lib.filterAttrs (
                      hostName: _:
                      let
                        host = topology.hosts.${hostName};
                      in
                      host.ipv4 != null || host.wireguardIpv4 != null
                    ) config.my.contracts.projections.hostFqdnOf
                  )
                )
                // (lib.mapAttrs'
                  (devName: fqdn: {
                    name = fqdn;
                    value = topology.devices.${devName}.ipv4;
                  })
                  (
                    lib.filterAttrs (
                      devName: _: topology.devices.${devName}.ipv4 != null
                    ) config.my.contracts.projections.deviceFqdnOf
                  )
                )
                // endpointMappings;
            };

            # Ad-blocking configuration
            blocking = {
              blackLists = {
                ads = [
                  "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
                ];
              };
              clientGroupsBlock = {
                default = [ "ads" ];
              };
              blockType = "zeroIp";
            };

            # Redis Caching
            redis = {
              address = "localhost:6379";
              database = 0;
            };

            # Caching settings
            caching = {
              minTime = "5m";
              maxTime = "30m";
              prefetching = true;
            };

            # Enable Prometheus metrics
            prometheus = {
              enable = true;
              path = "/metrics";
            };
          };
        };

        my.contracts.provides.blocky = {
          endpoints = {
            dns = {
              port = 53;
              protocol = "both";
              scope = "internal";
              directAccess = {
                enable = true;
                protocol = "both";
                interface = "all";
              };
              monitoring.http.enable = false;
            };

            api = {
              port = 4000;
              protocol = "tcp";
              scope = "internal";
              monitoring = {
                http.enable = false;
                scrape.enable = true;
                scrape.port = 4000;
              };
            };
          };
        };
      }
    ]
  );
}
