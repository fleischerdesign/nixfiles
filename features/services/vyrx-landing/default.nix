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
  outpost = config.my.features.services.authentik.server.embeddedOutpostAddress;

  # The portal's data is a projection of the service contracts, never a second list: the same
  # `accessGroups` the ingress enforces decides which tile a user sees, and the same `displayName` /
  # `group` / `dashboard.show` the cluster dashboard uses names it. A service added, renamed or
  # re-audienced in Nix appears here without touching the landing repository.
  flakeConfigurations =
    config._module.specialArgs.flake.nixosConfigurations or {
      "${config.networking.hostName}" = config;
    };

  # Live status is read from the collector on this host: the endpoint contracts already generate the
  # probes, and the collector is part of the same deployment. Reaching a collector on another host would
  # mean putting an unauthenticated query API on the mesh for nothing, so if this host does not run the
  # pipeline the route is simply absent - and the page says "unknown" instead of guessing.
  prometheusAddress =
    if config.my.features.services.monitoring.prometheus.enable or false then "127.0.0.1" else null;

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
                  id = if epName == "default" || epName == "web" then svcName else "${svcName}-${epName}";
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
      services = builtins.attrValues (
        lib.listToAttrs (map (entry: lib.nameValuePair entry.id entry) portalEntries)
      );
    }
  );

  # The static site plus the generated projection, served from one read-only store path.
  site = pkgs.runCommandLocal "vyrx-landing-portal" { } ''
    mkdir -p "$out"
    cp -r ${vyrxLandingPkg}/. "$out/"
    chmod -R u+w "$out"
    cp ${portal} "$out/portal.json"
  '';

  # The page is public and one hostname. `/api/me` is the only authenticated route: forward_auth runs
  # against the embedded outpost and, on success, the copy_headers values are echoed back - the browser
  # reads them from a same-origin response, so no token ever reaches JavaScript and no second origin is
  # involved. Without a session the outpost's redirect is left untouched, which `fetch(redirect:'manual')`
  # sees as "anonymous". `route` forces that order; the directive order inside a handle is not literal.
  customExtraConfig = ''
    root * ${site}

    handle /api/me {
      route {
        forward_auth ${outpost} {
          uri /outpost.goauthentik.io/auth/caddy
          copy_headers X-Authentik-Username X-Authentik-Groups X-Authentik-Email X-Authentik-Name
          trusted_proxies private_ranges
        }
        header X-Portal-Username "{http.request.header.X-Authentik-Username}"
        header X-Portal-Name "{http.request.header.X-Authentik-Name}"
        header X-Portal-Groups "{http.request.header.X-Authentik-Groups}"
        header Cache-Control "no-store"
        respond "" 200
      }
    }

    ${lib.optionalString (prometheusAddress != null) ''
      # Live status, same-origin. One fixed query and a fixed path: the browser never talks to the
      # collector, no PromQL is user-controlled, and `probe_success` is the same series the alerts read -
      # the portal and the alerting therefore agree by construction instead of by convention.
      handle /api/status {
        rewrite * /api/v1/query?query=probe_success
        reverse_proxy ${prometheusAddress}:9090
        header Cache-Control "public, max-age=10"
      }
    ''}
    import authentik

    handle {
      file_server
      try_files {path} {path}/index.html =404
    }
  '';
in
{
  options.my.features.services.vyrx-landing = {
    enable = lib.mkEnableOption "VYRX Enterprise Portal & Landing Page";
  };

  config = lib.mkIf cfg.enable {
    my.contracts.provides.vyrx-landing = {
      endpoints.web = {
        port = 80;
        protocol = "tcp";
        scope = "public";
        # The page itself is served by `customExtraConfig` and stays public; this value is what
        # registers a proxy application for `vyrx.de` in authentik, which is what lets the embedded
        # outpost answer `/api/me` at all (without a matching application it returns 404 for the host).
        # Publishing the fleet inventory is a deliberate decision, not an oversight: only `/api/me` is
        # personal, and it answers with the caller's own claims.
        auth = "authentik";
        accessGroups = [
          "family"
          "media-users"
          "infra-admins"
        ];
        adminGroups = portalAdminGroups;
        subdomain = "@";
        inherit customExtraConfig;
        dashboard = {
          show = false;
        };
      };
    };
  };
}
