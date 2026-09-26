{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.my.features.services.vyrx-landing;

  # The portal's data is a projection of the service contracts, never a second list: the same
  # `accessGroups` the ingress enforces decides which tile a user sees, and the same `displayName` /
  # `group` / `dashboard.show` the cluster dashboard uses names it. A service added, renamed or
  # re-audienced in Nix appears in the projection without touching the landing repository.
  flake = config._module.specialArgs.flake or { };
  flakeConfigurations =
    flake.nixosConfigurations or {
      "${config.networking.hostName}" = config;
    };

  endpointLib = import ../../../lib/endpoints.nix { inherit lib; };

  # Live status is read from the collector on this host: the endpoint contracts already generate the
  # probes, and the collector is part of the same deployment. Reaching a collector on another host would
  # mean putting an unauthenticated query API on the mesh for nothing, so if this host does not run the
  # pipeline the route is simply absent - and the page says "unknown" instead of guessing.
  prometheusAddress =
    if config.my.features.services.monitoring.prometheus.enable or false then "127.0.0.1" else null;

  # --- the projection -------------------------------------------------------------------------------
  # The portal reads its fleet at runtime; this file is what it reads. Every fact is projected from a
  # contract, so the portal cannot show a service the fleet does not serve. It carries no host, no
  # address, no port and no person: a projection that named a machine would be an address book, and one
  # that named a user would be a membership - which the identity model keeps in Authentik.
  #
  # `generatedAt` is the source revision's timestamp, not this build's: a build timestamp cannot be
  # read in a pure evaluation and would make the projection irreproducible, and the app only shows it
  # next to `revision` ("built is not rolled out"). Nix hands it as `YYYYMMDDHHMMSS`, so it is
  # re-spelled to ISO-8601 here.
  revision = flake.rev or (flake.dirtyRev or "unknown");
  generatedAt =
    let
      stamp = flake.lastModifiedDate or null;
    in
    if stamp != null && builtins.stringLength stamp == 14 then
      "${builtins.substring 0 4 stamp}-${builtins.substring 4 2 stamp}-${builtins.substring 6 2 stamp}T${builtins.substring 8 2 stamp}:${builtins.substring 10 2 stamp}:${builtins.substring 12 2 stamp}Z"
    else
      "1970-01-01T00:00:00Z";

  # The labels the portal shows are localized. The contract offers one string for a tile name and a
  # per-locale description; a product name is language-neutral, so it is repeated, while the summary
  # is already per locale. `de` and `en` are always present because the app's schema needs both.
  localized =
    text:
    lib.genAttrs (lib.unique (
      [
        "de"
        "en"
      ]
      ++ config.my.portal.locales
    )) (_: text);
  serviceName = svcName: ep: if ep.displayName != null then ep.displayName else svcName;
  summaryOf =
    svcName: ep:
    let
      fallback = serviceName svcName ep;
    in
    {
      de = ep.dashboard.description.de or fallback;
      en = ep.dashboard.description.en or (ep.dashboard.description.de or fallback);
    };

  # A category id is derived from the declared label so it is stable across redeploys; renaming the
  # label is then a deliberate change of id. The contract offers no per-locale category copy, so both
  # languages carry the one string (the app falls back to German for an unknown tag anyway).
  categoryOf = ep: if ep.group != null then ep.group else "Services";
  slug =
    text:
    let
      parts = builtins.filter builtins.isString (builtins.split "[^a-zA-Z0-9]+" (lib.toLower text));
      nonEmpty = builtins.filter (part: part != "") parts;
    in
    if nonEmpty == [ ] then "services" else lib.concatStringsSep "-" nonEmpty;

  # How the portal reads a service and what it may do with it. The shape is `vyrx.de`'s adapter
  # declaration; a service without a readout and without actions has no entry at all, so the portal
  # honestly reports "unsupported" instead of reading nothing.
  capabilityOf =
    contract:
    let
      readout = contract.readouts;
      actions = lib.mapAttrsToList (actionId: action: { id = actionId; } // action) contract.actions;
      hasReadout =
        readout != null && (readout.read != null || readout.fields != [ ] || readout.lists != [ ]);
    in
    if !hasReadout && actions == [ ] then
      null
    else
      {
        driver = if readout != null then readout.driver else "http-json";
        auth = if readout != null then readout.auth else "none";
        read = lib.optionalAttrs (readout != null && readout.read != null) {
          method = "GET";
          inherit (readout.read) path;
        };
        fields = if readout != null then readout.fields else [ ];
        lists = if readout != null then readout.lists else [ ];
        actions = actions;
      };

  # Every endpoint a contract displays becomes one service; `dependsOn` and `actions` come from the
  # contract, because they describe the service, not a single endpoint. The `icon` is optional in the
  # interface, so the dashboard's neutral default is left out rather than spelled as a symbol name.
  portalEntries = lib.concatMap (
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
                categoryLabel = categoryOf ep;
                capability = capabilityOf contract;
                service = {
                  id = endpointLib.endpointName svcName epName;
                  name = localized (serviceName svcName ep);
                  summary = summaryOf svcName ep;
                  categoryId = slug (categoryOf ep);
                  scope = ep.scope;
                  accessGroups = ep.accessGroups;
                  adminGroups = ep.adminGroups;
                  dependsOn = contract.dependsOn;
                  actions = builtins.attrNames contract.actions;
                  url = "https://${ep.canonicalDomain}";
                  # Whether anything measures it. A service without a probe is not "unknown" - the
                  # projection says so, and the page shows that instead of inventing a state.
                  monitored = ep.monitoring.http.enable;
                }
                // lib.optionalAttrs (ep.dashboard.icon != "default") { inherit (ep.dashboard) icon; };
              }
            ]
          ) contract.endpoints
        )
      ) provides
    )
  ) (builtins.attrNames flakeConfigurations);

  # One entry per id: several hosts may project the same service, and the last declaration wins.
  entries = builtins.attrValues (
    lib.listToAttrs (map (entry: lib.nameValuePair entry.service.id entry) portalEntries)
  );

  # Categories are the union of what the services declared, sorted by id so the order is stable. The
  # contract names a category only by its dashboard label, so the order is the only thing left to pick;
  # the app sorts by it and breaks ties by id.
  categories =
    let
      labelById = lib.foldl' (
        acc: entry: acc // { ${entry.service.categoryId} = entry.categoryLabel; }
      ) { } entries;
    in
    lib.imap0 (index: id: {
      inherit id;
      label = localized labelById.${id};
      order = (index + 1) * 10;
    }) (lib.sort (a: b: a < b) (builtins.attrNames labelById));

  # Who administers the portal itself. The projection carries it so the app can gate its admin view
  # without knowing a group name: the page stays generic, the audience is configuration.
  portalAdminGroups = [ "infra-admins" ];

  fleet = pkgs.writeText "fleet.json" (
    builtins.toJSON {
      schema = 1;
      inherit revision generatedAt;
      locales = config.my.portal.locales;
      adminGroups = portalAdminGroups;
      inherit categories;
      services = map (entry: entry.service) entries;
    }
  );

  adapters = pkgs.writeText "adapters.json" (
    builtins.toJSON {
      schema = 1;
      services = lib.listToAttrs (
        map (entry: lib.nameValuePair entry.service.id entry.capability) (
          lib.filter (entry: entry.capability != null) entries
        )
      );
    }
  );

  # The built portal, unmodified: it reads the projection at runtime, so there is no catalogue build
  # input and nothing is rendered per service. `client/` holds the prerendered public pages and their
  # assets, `server/` the Node entry that answers every page and API route.
  site = inputs.vyrx-landing.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # The projection travels next to the app instead of inside it: one artifact carries the entry point
  # and the files it reads, the unit points at them in place, and a new projection is a new file rather
  # than a rebuild of the app.
  portalArtifact = pkgs.runCommand "vyrx-portal" { } ''
    mkdir -p $out
    cp -a ${site}/. $out/
    # `cp -a` copies the store directory's read-only mode onto $out as well; the two projections are
    # added here, so the top level is made writable again. The copied tree stays as it was built.
    chmod u+w $out
    cp ${fleet} $out/fleet.json
    cp ${adapters} $out/adapters.json
  '';

  # The API port. The process serves everything - pages, assets and API - so this is the port the
  # endpoint declares, not a private one behind a hand-written proxy.
  portalApiPort = 4317;

in
{
  options.my.features.services.vyrx-landing = {
    enable = lib.mkEnableOption "VYRX Enterprise Portal & Landing Page";

    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      description = ''
        The built portal with this host's projections next to it: the Node entry point, the client tree
        and `fleet.json` / `adapters.json`. The projection is read at runtime, not compiled in.
      '';
    };

    projection = lib.mkOption {
      type = lib.types.path;
      readOnly = true;
      description = ''
        The fleet projection this host's contracts produce - the file the portal reads at runtime. It
        carries services, categories, dependencies and actions, and no address and no person.
      '';
    };

    adapters = lib.mkOption {
      type = lib.types.path;
      readOnly = true;
      description = ''
        The adapter declaration this host's contracts produce: how the portal reads each projected
        service and which actions it may trigger, without naming a product.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    my.features.services.vyrx-landing.package = portalArtifact;
    my.features.services.vyrx-landing.projection = fleet;
    my.features.services.vyrx-landing.adapters = adapters;

    # The portal's API and pages are one process. It reaches the collector over the mesh and, later, the
    # services themselves; what may reach it is decided by the firewall and the ingress, like every other
    # service in this fleet.
    systemd.services.vyrx-portal-api = {
      description = "VYRX portal (landing page and its API)";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.nodejs_24}/bin/node ${portalArtifact}/server/entry.mjs";
        Environment = [
          # Loopback, because the ingress proxies to `127.0.0.1:<port>` for its own host - and because it is
          # stricter: this process trusts the identity headers the proxy forwards, so nothing but the proxy
          # should be able to reach it. `directAccess` stays off, so the firewall opens nothing either.
          "HOST=127.0.0.1"
          "PORT=${toString portalApiPort}"
          "PORTAL_FLEET=${portalArtifact}/fleet.json"
          "PORTAL_ADAPTERS=${portalArtifact}/adapters.json"
          # Favorites, reports and the action log are this host's own state, not a projection: the
          # dynamic user gets a state directory systemd makes writable under `ProtectSystem = "strict"`.
          "PORTAL_STORE=%S/vyrx-portal/portal.sqlite"
        ]
        ++ lib.optional (
          prometheusAddress != null
        ) "PORTAL_PROMETHEUS_URL=http://${prometheusAddress}:9090";
        # `PORTAL_OPERATIONS` is deliberately unset: backups, certificates and tree health are
        # measurements this fleet does not write yet (a restic snapshot, an ACME expiry). The portal
        # shows an honest "unknown" until a measured writer exists; deriving them from the contracts
        # would be a second truth. `PORTAL_STORE` is set above for the same reason state belongs here.
        StateDirectory = "vyrx-portal";
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
        # What answers without a session: the public pages and their assets. `/` and `/en` are
        # server-rendered (they read the identity headers) but still public. Every workspace page -
        # `/services`, `/knowledge`, `/status`, `/account`, `/admin` - is authorised and is not here,
        # and neither are `/api/status` or `/api/health`: the projection is read server-side, so the
        # status API must not leak what it measured to an anonymous caller.
        unauthenticatedPaths = [
          "/"
          "/project/*"
          "/help/*"
          "/en"
          "/en/project/*"
          "/en/help/*"
          "/404.html"
          "/en/404.html"
          "/robots.txt"
          "/_astro/*"
          "/favicon.ico"
          "/favicon.svg"
          "/apple-touch-icon.png"
          "/icon-192.png"
          "/icon-512.png"
          "/icon-maskable-512.png"
          "/site.webmanifest"
        ];
        dashboard = {
          show = false;
        };
      };
    };
  };
}
