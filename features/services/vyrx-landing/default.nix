{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.my.features.services.vyrx-landing;
  vyrxLandingPkg = inputs.vyrx-landing.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # The portal's data is a projection of the service contracts, never a second list: the same
  # `accessGroups` the ingress enforces decides which tile a user sees, and the same `displayName` /
  # `group` / `dashboard.show` the cluster dashboard uses names it. A service added, renamed or
  # re-audienced in Nix appears here without touching the landing repository.
  flakeConfigurations =
    config._module.specialArgs.flake.nixosConfigurations or {
      "${config.networking.hostName}" = config;
    };

  endpointLib = import ../../../lib/endpoints.nix { inherit lib; };
  topology = config.my.topology;

  # Live status is read from the collector on this host: the endpoint contracts already generate the
  # probes, and the collector is part of the same deployment. Reaching a collector on another host would
  # mean putting an unauthenticated query API on the mesh for nothing, so if this host does not run the
  # pipeline the route is simply absent - and the page says "unknown" instead of guessing.
  prometheusAddress =
    if config.my.features.services.monitoring.prometheus.enable or false then "127.0.0.1" else null;

  # The fleet view. Every field is a fact from the inventory: the zone and its CIDR, the addresses, the
  # relay flag, whether this is the ingress, and `hostType` - the role the host is assigned. The service
  # list is the host's own `provides`, so nothing here is written a second time, and the landing no
  # longer carries a `mesh.json` at all.
  portalHosts = lib.sort (a: b: a.name < b.name) (
    map (
      name:
      let
        host = topology.hosts.${name} or { };
        provides = flakeConfigurations.${name}.config.my.contracts.provides or { };
      in
      {
        inherit name;
        type = host.hostType or "server";
        zone = host.zone or null;
        cidr = (topology.subnets.${host.zone} or { }).cidr or null;
        ipv4 = host.ipv4 or null;
        wireguardIpv4 = host.wireguardIpv4 or null;
        relay = host.wireguardRelay or false;
        ingress = name == topology.ingressHost;
        # Whether anything probes this host at all. A host without monitoring is not "unknown" - the
        # portal knows it is unmonitored, and says so instead of inventing a state.
        monitored = lib.any (ep: ep.monitoring.scrape.enable) (
          lib.concatLists (lib.mapAttrsToList (_: c: lib.attrValues c.endpoints) provides)
        );
        services = lib.sort (a: b: a < b) (builtins.attrNames provides);
      }
    ) (builtins.attrNames flakeConfigurations)
  );

  portalEntries = lib.concatLists (
    map (
      hostName:
      let
        provides = flakeConfigurations.${hostName}.config.my.contracts.provides or { };
      in
      lib.concatLists (
        lib.mapAttrsToList (
          svcName: contract:
          lib.concatLists (
            lib.mapAttrsToList (
              epName: ep:
              lib.optionals (ep.dashboard.show && ep.canonicalDomain != null) [
                {
                  id = endpointLib.endpointName svcName epName;
                  name = if ep.displayName != null then ep.displayName else svcName;
                  description = ep.dashboard.description;
                  url = "https://${ep.canonicalDomain}";
                  category = if ep.group != null then ep.group else "Services";
                  icon = ep.dashboard.icon;
                  # Where the service is reachable from, so the tile can say "LAN" or "Mesh" instead of
                  # handing out a name that only resolves inside the network.
                  scope = ep.scope;
                  groups = ep.accessGroups;
                  admin = ep.adminGroups;
                  # The collector labels a probe with the same endpoint name this id carries, so the tile
                  # asks `/api/status` for exactly its own series. Whether it is probed at all is the
                  # contract's decision (`monitoring.http.enable`), not the page's.
                  monitored = ep.monitoring.http.enable;
                }
              ]
            ) contract.endpoints
          )
        ) provides
      )
    ) (builtins.attrNames flakeConfigurations)
  );

  # Who administers the portal itself. The catalogue carries it so the app can gate its admin view
  # without knowing a group name: the page stays generic, the audience is configuration.
  portalAdminGroups = [ "infra-admins" ];

  # One entry per id: several hosts may project the same service, and the last declaration wins.
  portal = pkgs.writeText "portal.json" (
    builtins.toJSON {
      adminGroups = portalAdminGroups;
      locales = config.my.portal.locales;
      hosts = portalHosts;
      services = builtins.attrValues (
        lib.listToAttrs (map (entry: lib.nameValuePair entry.id entry) portalEntries)
      );
    }
  );

  # The built landing: `client/` holds the prerendered pages and their assets, `server/` the Node entry
  # that answers the API routes. One build, so a page and the endpoint it calls cannot be from different
  # versions.
  site = pkgs.runCommandLocal "vyrx-landing-portal" { } ''
    mkdir -p "$out"
    cp -r ${vyrxLandingPkg}/. "$out/"
    chmod -R u+w "$out"
    cp ${portal} "$out/client/portal.json"
  '';

  # The API port. The process serves everything - pages, assets and API - so this is the port the
  # endpoint declares, not a private one behind a hand-written proxy.
  portalApiPort = 4317;

in
{
  options.my.features.services.vyrx-landing = {
    enable = lib.mkEnableOption "VYRX Enterprise Portal & Landing Page";
  };

  config = lib.mkIf cfg.enable {
    # The portal's API and pages are one process. It reaches the collector over the mesh and, later, the
    # services themselves; what may reach it is decided by the firewall and the ingress, like every other
    # service in this fleet.
    systemd.services.vyrx-portal-api = {
      description = "VYRX portal (landing page and its API)";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.nodejs_22}/bin/node ${site}/server/entry.mjs";
        Environment = [
          # Loopback, because the ingress proxies to `127.0.0.1:<port>` for its own host - and because it is
          # stricter: this process trusts the identity headers the proxy forwards, so nothing but the proxy
          # should be able to reach it. `directAccess` stays off, so the firewall opens nothing either.
          "HOST=127.0.0.1"
          "PORT=${toString portalApiPort}"
        ]
        ++ lib.optional (
          prometheusAddress != null
        ) "PORTAL_PROMETHEUS_URL=http://${prometheusAddress}:9090";
        Restart = "on-failure";
        RestartSec = "2s";
        DynamicUser = true;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
      };
    };

    my.contracts.provides.vyrx-landing = {
      # An ordinary service: one process, one port, one vhost. It serves its own pages, its assets and its
      # API, so the ingress does exactly what it does for every other service - authenticate, then proxy -
      # and knows nothing about files, route names or a collector address.
      endpoints.web = {
        port = portalApiPort;
        protocol = "tcp";
        scope = "public";
        # This value registers a proxy application for `vyrx.de` in authentik, which is what lets the
        # embedded outpost answer `/api/me` at all (without a matching application it returns 404 for the
        # host). Publishing the fleet inventory is a deliberate decision, not an oversight.
        auth = "authentik";
        accessGroups = [
          "family"
          "media-users"
          "infra-admins"
        ];
        adminGroups = portalAdminGroups;
        subdomain = "@";
        # What answers without a session: the pages and their assets (a visitor sees the fleet inventory)
        # and the two status routes that feed the landing's live data. Everything else - above all
        # `/api/me` - needs a session, which is what makes the identity it reports trustworthy.
        unauthenticatedPaths = [
          "/"
          "/en"
          "/en/*"
          "/404.html"
          "/robots.txt"
          "/portal.json"
          "/_astro/*"
          "/api/status"
          "/api/hosts"
        ];
        dashboard = {
          show = false;
        };
      };
    };
  };
}
