# contracts/endpoints/default.nix
# Endpoint Contract Specification & Ingress Protocol.
# Defines the typed schema for service network endpoints (ports, scopes, auth policies, OIDC, URLs)
# and projects local direct-access endpoints into host firewall rules.
{
  config,
  lib,
  ...
}:

let
  cfg = config.my.contracts;

  # Two things are shared rather than repeated: how a rule is spelled (`lib/nftables.nix`) and the
  # lattice's vocabulary, both coming from the modules that own them - so a policy here and the same
  # policy projected elsewhere cannot drift apart.
  nft = import ../../lib/nftables.nix { inherit lib; };
  endpointLib = import ../../lib/endpoints.nix { inherit lib; };
  levels = config.my.topology.trustLevels;

  # Submodule for Endpoint Contract
  endpointContractSubmodule = lib.types.submodule (submod: {
    options = {
      port = lib.mkOption {
        type = lib.types.port;
        description = "Internal network port the service listens on";
      };

      protocol = lib.mkOption {
        type = lib.types.enum [
          "tcp"
          "udp"
          "both"
        ];
        default = "tcp";
        description = "Transport layer protocol";
      };

      scope = lib.mkOption {
        type = lib.types.enum [
          "public"
          "internal"
          "mesh"
          "isolated"
        ];
        default = "internal";
        description = "Ingress exposure scope (public wildcard, internal LAN, wireguard mesh, or isolated)";
      };

      ingress = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Whether the HTTP ingress terminates this endpoint - a Caddy virtual host and the
          certificate that goes with it. An endpoint another component terminates itself (a
          resolver's DNS-over-TLS listener) sets this to false: its name is still projected
          into public DNS and its port into the host firewall, but no virtual host and no
          ingress certificate are created for it.
        '';
      };

      auth = lib.mkOption {
        type = lib.types.enum [
          "none"
          "authentik"
          "proxy-pass"
          "oidc"
        ];
        default = "none";
        description = "Authentication enforcement policy";
      };

      oidc = {
        enable = lib.mkEnableOption "Expose endpoint as Authentik OIDC Application";

        clientId = lib.mkOption {
          type = lib.types.str;
          default = submod.config._module.args.name or "app";
          description = "OIDC Client ID (defaults to endpoint attribute name)";
        };

        clientSecret = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Plaintext client secret (discouraged in favor of clientSecretEnv or secretPath)";
        };

        clientSecretEnv = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Environment variable name containing the client secret (e.g. AUTHENTIK_OIDC_SECRET_...)";
        };

        secretPath = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "SOPS secret path containing the client secret (e.g. 'services/apps/paperless_oidc_secret')";
        };

        redirectPaths = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Relative redirect callback paths (e.g. [ '/api/auth/callback' ])";
        };

        redirectUris = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Explicit redirect URIs. If empty, automatically synthesized from canonicalDomain + extraDomains + redirectPaths.";
        };

        subMode = lib.mkOption {
          type = lib.types.enum [
            "hashed_user_id"
            "user_username"
            "user_email"
            "user_upn"
          ];
          default = "hashed_user_id";
          description = "Subject mode identifier mapping";
        };

        includeClaimsInIdToken = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether to include user claims directly in the ID token";
        };

        grantTypes = lib.mkOption {
          type = lib.types.listOf (
            lib.types.enum [
              "authorization_code"
              "implicit"
              "hybrid"
              "refresh_token"
              "client_credentials"
              "password"
              "device_code"
            ]
          );
          default = [
            "authorization_code"
            "refresh_token"
          ];
          description = "Allowed OAuth2 grant types for the provider";
        };

        signingKey = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = "authentik Internal JWT Certificate";
          description = "Name of the certificate/keypair in Authentik used to sign ID and access tokens for JWKS";
        };

        propertyMappings = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [
            "openid"
            "email"
            "profile"
          ];
          description = "Authentik scope mappings attached to the provider to populate scopes and claims (e.g. openid, email, profile)";
        };
      };

      # Who may use this endpoint. One declaration per service, projected three ways: the ingress gate
      # (an Authentik policy binding on the application for `auth = "authentik"` or `"oidc"`), the
      # directory filter (an LDAP consumer's memberOf), and the portal (vyrx.de shows a user only what
      # these groups allow). Deliberately no default: a service published through the ingress without
      # naming its audience has no policy, and the compiler refuses to build it.
      accessGroups = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        # `apply` is the desugaring, and it is one line on purpose: `accessUsers` is a spelling of an
        # audience, not a second audience. The ingress binding, the directory filter and the portal all
        # read `accessGroups`, so none of them can miss the derived groups - which is the failure a
        # second field would have produced: an LDAP filter naming no group locks everyone out while the
        # deploy stays green.
        apply =
          groups: groups ++ map (username: endpointLib.audienceGroup username) submod.config.accessUsers;
        description = "Authentik groups whose members may use this endpoint, plus one group per declared `accessUsers`.";
      };

      # An audience named by people instead of by role. Each username becomes its own group
      # (`lib/endpoints.nix` `audienceGroup`) and the compiler declares its membership, so this is the
      # same mechanism as a role group - only with one member, and declared.
      accessUsers = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Usernames that may use this endpoint, each through its own audience group.";
      };

      # A group this endpoint accepted before its audience became a declaration. An apply adds and
      # updates; it does not remove a binding that is no longer named, so retiring an audience takes a
      # declaration of its own - the tombstone - or the old binding keeps granting what the change was
      # meant to end (docs/identity.md §11.3).
      retiredAccessGroups = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Groups this endpoint no longer accepts; each is tombstoned on apply.";
      };

      adminGroups = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Groups whose members administer this endpoint (usually a subset of accessGroups).";
      };

      # Directory authentication, parallel to `oidc` and on the same axis: `auth` says who gets through
      # the ingress, this says where the application's users come from. LDAP is not an ingress concern
      # - the proxy speaks no LDAP - so it does not belong in the `auth` enum. Its audience is the
      # endpoint's, so it does not restate it.
      ldap = {
        enable = lib.mkEnableOption "Authenticate this endpoint's users against the Authentik LDAP directory";

        accessGroups = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = submod.config.accessGroups;
          description = "Inherited from the endpoint's `accessGroups`; the directory filter is a projection of it.";
        };

        adminGroups = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = submod.config.adminGroups;
          description = "Inherited from the endpoint's `adminGroups`.";
        };

        baseDn = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Directory base DN; null uses the one the LDAP provider declares.";
        };

        secretPath = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            SOPS path holding the app password this service binds with. An LDAP bind takes a username
            and a password, so this is an app password and not an API token, which authenticates to the
            HTTP API only. Null derives `services/authentik/consumers/<endpoint-name>-ldap-password`.
          '';
        };
      };

      domain = lib.mkOption {
        type = lib.types.str;
        default = config.my.topology.domain;
        description = "Apex zone for derived names. Naming never depends on the serving host.";
      };

      fqdn = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "vyrx.de";
        description = ''
          Explicit FQDN override (escape hatch). Only for names that cannot follow the plane
          scheme: the zone apex, or a foreign domain.
        '';
      };

      aliases = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Legacy names published as aliases during a rename window.";
      };

      publicExempt = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Reason a public endpoint may run with auth = \"none\" (invariant I9).";
      };

      subdomain = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Canonical subdomain prefix (e.g. 'jellyfin' -> jellyfin.vyrx.de)";
      };

      extraDomains = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Additional domains/aliases associated with this endpoint";
      };

      websocket = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Service requires WebSocket upgrade forwarding";
      };

      unauthenticatedPaths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Path globs bypassing edge auth for self-authenticating webhooks/tokens";
      };

      machineClientsBypassAuth = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Bypass forward-auth for non-browser WebSocket upgrades (e.g. device/node tokens)";
      };

      customExtraConfig = lib.mkOption {
        type = lib.types.nullOr lib.types.lines;
        default = null;
        description = ''
          Fully custom Caddyfile directives that replace the generated proxy block. Prefer
          `proxyOptions`: this option ignores the projected upstream target and therefore
          cannot be used by the ingress engine.
        '';
      };

      proxyOptions = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = ''
          Extra directives placed inside the generated `reverse_proxy` block, e.g.
          `flush_interval -1` for streaming. Applied on every host that serves the endpoint,
          including the ingress, so the upstream target stays projected.
        '';
      };

      crowdsec = {
        exemptScenarios = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = ''
            List of CrowdSec scenario names that are explicitly exempted from triggering bans
            when accessing this endpoint (e.g. ['crowdsecurity/http-crawl-non_statics'] for binary caches).
          '';
        };
      };

      directAccess = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Open this port directly in the host firewall";
        };

        protocol = lib.mkOption {
          type = lib.types.enum [
            "tcp"
            "udp"
            "both"
          ];
          default = "tcp";
          description = "Network protocol to open in the firewall (tcp, udp, or both)";
        };

        interface = lib.mkOption {
          type = lib.types.enum [
            "all"
            "wireguard"
            "local"
          ];
          default = "all";
          description = "Network interface to bind the firewall rule to (all, wireguard, or local)";
        };

        from = lib.mkOption {
          type = lib.types.listOf (lib.types.enum levels);
          default = levels;
          description = ''
            Trust levels whose nodes may reach this port over the mesh. It restricts, never opens: the
            port is opened by `interface`, and this says who of the mesh may actually use it. A port that
            belongs to the local network but not to the fleet's infrastructure (the administrative path)
            names the levels it is for.
          '';
        };
      };

      healthProbePath = lib.mkOption {
        type = lib.types.str;
        default = "/";
        description = "HTTP path for liveness and health checks";
      };

      monitoring = {
        http = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable HTTP monitoring probe";
          };

          group = lib.mkOption {
            type = lib.types.str;
            default = "HTTP";
            description = "Monitoring probe category group";
          };

          path = lib.mkOption {
            type = lib.types.str;
            default = "/";
            description = "HTTP probe path";
          };
        };

        tcp = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable TCP monitoring probe";
          };

          group = lib.mkOption {
            type = lib.types.str;
            default = "Infrastructure";
            description = "Monitoring probe category group";
          };
        };

        scrape = {
          enable = lib.mkEnableOption "Prometheus scrape target for this service";

          port = lib.mkOption {
            type = lib.types.port;
            default = 80;
            description = "Port to scrape Prometheus metrics from (defaults to service port)";
          };

          path = lib.mkOption {
            type = lib.types.str;
            default = "/metrics";
            description = "Metrics endpoint path";
          };
        };
      };

      displayName = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = submod.config.dashboard.displayName;
        description = "Human-readable display name for SSO portals and dashboards (e.g. 'Mainsail (Klipper)')";
      };

      group = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = submod.config.dashboard.category;
        description = "Logical group / category for SSO portals and dashboards (e.g. 'Media', '3D Printing', 'AI & Agents')";
      };

      # Dashboard Metadata (Compiles directly into cluster dashboard)
      dashboard = {
        show = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to display this service tile on the cluster dashboard";
        };
        displayName = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Human-readable tile title (defaults to endpoint name)";
        };
        category = lib.mkOption {
          type = lib.types.str;
          default = "Services";
          description = "Dashboard category grouping (e.g. Media, Infrastructure, Smart Home)";
        };
        icon = lib.mkOption {
          type = lib.types.str;
          default = "default";
          description = "Dashboard icon identifier";
        };
        description = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          description = ''
            Short copy per locale tag, e.g. `{ de = "..."; en = "..."; }`. The tag set is
            `my.portal.locales`, and the assertion below fails evaluation when one is missing - so a
            third language is data, not a schema change.
          '';
        };
      };

      # Computed Read-Only Options
      planeSuffix = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        readOnly = true;
        description = "DNS suffix contributed by the exposure scope (null = no name).";
      };

      canonicalDomain = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        readOnly = true;
        description = "The fully resolved FQDN of the service. Null if scope is isolated.";
      };

      publicUrl = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        readOnly = true;
        description = "The public HTTPS URL of the service. Null if canonicalDomain is null.";
      };

      localUrl = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
        description = "The local loopback HTTP URL used for internal health probes.";
      };
    };

    config = {
      planeSuffix =
        if submod.config.scope == "public" then
          ""
        else if submod.config.scope == "internal" then
          "lan."
        else if submod.config.scope == "mesh" then
          "mesh."
        else
          null;

      canonicalDomain =
        if submod.config.fqdn != null then
          submod.config.fqdn
        else if submod.config.planeSuffix == null then
          null
        else if submod.config.subdomain == null || submod.config.subdomain == "" then
          null
        else if submod.config.subdomain == "@" then
          submod.config.domain
        else
          "${submod.config.subdomain}.${submod.config.planeSuffix}${submod.config.domain}";

      publicUrl =
        if submod.config.canonicalDomain != null then "https://${submod.config.canonicalDomain}" else null;

      localUrl = "http://127.0.0.1:${toString submod.config.port}";

      monitoring.scrape.port = lib.mkDefault submod.config.port;

      oidc.redirectUris =
        let
          epConfig = submod.config;
          allDomains =
            (lib.optional (epConfig.canonicalDomain != null) epConfig.canonicalDomain) ++ epConfig.extraDomains;
        in
        lib.mkDefault (
          lib.concatMap (dom: map (path: "https://${dom}${path}") epConfig.oidc.redirectPaths) allDomains
        );
    };
  });

  # --- what the portal reads, and what it may do ----------------------------------------------------
  # A readout is not a dashboard: `dashboard` says how a tile looks, these say what the portal may read
  # and do. They live beside `endpoints`, not inside `dashboard`, because a service has one readout
  # however many endpoints it exposes, and because the ingress, the dashboard and the portal must not
  # each grow their own copy of the same fact.
  #
  # The shape is the app's own interface (`vyrx.de/src/lib/adapters.ts`): the generic `http-json`
  # driver reads one path and picks declared fields out of the JSON by pointer. There is no product
  # knowledge here - a driver that is not `http-json` is an honest "unsupported", not an error.
  readoutFieldSubmodule = lib.types.submodule {
    options = {
      id = lib.mkOption {
        type = lib.types.str;
        description = "Field identifier, a lowercase slug";
      };

      label = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        description = ''
          Copy per locale tag, e.g. `{ de = "Version"; en = "Version"; }`. The tag set is
          `my.portal.locales`, and the assertion below fails when one is missing.
        '';
      };

      type = lib.mkOption {
        type = lib.types.enum [
          "text"
          "number"
          "duration"
          "status"
          "bytes"
          "date"
        ];
        description = "How the value is rendered; the type, not the driver, decides.";
      };

      pointer = lib.mkOption {
        type = lib.types.str;
        description = "RFC 6901 pointer into the response, starting with '/'.";
      };
    };
  };

  readoutListSubmodule = lib.types.submodule {
    options = {
      id = lib.mkOption {
        type = lib.types.str;
        description = "List identifier, a lowercase slug";
      };

      label = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        description = "Copy per locale tag, as for a field.";
      };

      pointer = lib.mkOption {
        type = lib.types.str;
        description = "RFC 6901 pointer to the array in the response, starting with '/'.";
      };

      max = lib.mkOption {
        type = lib.types.int;
        default = 5;
        description = ''
          Most rows the portal reads. Bounded by the assertion below: a declaration may not ask for
          "all rows", because the portal must not become a mirror of another service's data.
        '';
      };

      items = lib.mkOption {
        type = lib.types.nonEmptyListOf readoutFieldSubmodule;
        description = "The fields of one row; a list without fields carries nothing.";
      };
    };
  };

  readoutSubmodule = lib.types.submodule {
    options = {
      driver = lib.mkOption {
        type = lib.types.str;
        default = "http-json";
        description = "The driver that performs the read; `http-json` is the generic one.";
      };

      auth = lib.mkOption {
        type = lib.types.enum [
          "none"
          "bearer"
          "header"
          "basic"
        ];
        default = "none";
        description = ''
          How the request authenticates. The credential itself comes from the environment, never from
          the declaration and never into the browser.
        '';
      };

      read = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.submodule {
            options.path = lib.mkOption {
              type = lib.types.str;
              description = "Path of the read request, starting with '/'; the method is always GET.";
            };
          }
        );
        default = null;
        description = ''
          The request whose response the fields and lists point into. Null is allowed for a service
          that only declares actions; a declaration with fields or lists must name it (asserted below).
        '';
      };

      fields = lib.mkOption {
        type = lib.types.listOf readoutFieldSubmodule;
        default = [ ];
        description = "Scalar values read from the response.";
      };

      lists = lib.mkOption {
        type = lib.types.listOf readoutListSubmodule;
        default = [ ];
        description = "Row collections read from the response.";
      };
    };
  };

  actionSubmodule = lib.types.submodule {
    options = {
      label = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        description = "Copy per locale tag, as for a field.";
      };

      confirm = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        description = "Sentence shown before the action runs; it must name both locales (asserted below).";
      };

      method = lib.mkOption {
        type = lib.types.enum [
          "POST"
          "PUT"
          "DELETE"
        ];
        description = "HTTP method the action calls.";
      };

      path = lib.mkOption {
        type = lib.types.str;
        description = "Path the action calls, starting with '/'.";
      };

      permission = lib.mkOption {
        type = lib.types.enum [ "admin" ];
        default = "admin";
        description = "Who may trigger the action; only administrators, for now.";
      };
    };
  };

  # Flatten all local endpoints across all declared contracts on this host
  localEndpointsList = lib.concatLists (
    lib.mapAttrsToList (_svcName: contract: lib.attrValues contract.endpoints) cfg.provides
  );

  # --- what an endpoint exposes, and to whom ---------------------------------------------------------
  # Two things are being said, and one port list cannot say both: a port opened for the local network is
  # reachable from every address on it - that is what "the local network is one trusted segment" means -
  # while the mesh is judged by who is asking, which is the trust lattice, written in levels and rendered
  # into addresses here.
  #
  # Every rule is an allow. Under the nftables implementation these land in the firewall's `input-allow`
  # chain *behind* the declarative port accepts, so a deny here would never be reached - and it is not
  # needed, because the chain's own policy is `drop`: what nobody allowed is closed. The previous shape
  # opened a port for everyone and denied the mesh levels on top, which is why the deny had to be inserted
  # at the head of the chain with a shell command, and why a withdrawn one stayed there forever.
  #
  # A named endpoint is proxied by an ingress, and the ingress is a host of the `mesh` zone: a proxy always
  # implies that level, whatever the endpoint declares for direct use. That is also why the mesh side is
  # narrower than it used to be - it is no longer "every mesh member", but the levels the endpoint is for.
  accessRules = lib.concatMap (
    ep:
    let
      protos =
        if ep.directAccess.protocol == "both" then
          [
            "tcp"
            "udp"
          ]
        else
          [ ep.directAccess.protocol ];
      levels = lib.unique (ep.directAccess.from ++ lib.optional (ep.canonicalDomain != null) "mesh");
      meshSources = nft.sourcesOfTrust config.my.topology levels;
      v4 = lib.filter (address: !(lib.hasInfix ":" address)) meshSources;
      v6 = lib.filter (address: lib.hasInfix ":" address) meshSources;
      dport = toString ep.port;
      localRule =
        proto:
        nft.rule [
          ''iifname != "wg0"''
          "${proto} dport ${dport}"
          "accept"
        ];
      meshRules =
        proto:
        lib.optionals (v4 != [ ]) [
          (nft.rule [
            ''iifname "wg0"''
            "ip saddr ${nft.addressSet v4}"
            "${proto} dport ${dport}"
            "accept"
          ])
        ]
        ++ lib.optionals (v6 != [ ]) [
          (nft.rule [
            ''iifname "wg0"''
            "ip6 saddr ${nft.addressSet v6}"
            "${proto} dport ${dport}"
            "accept"
          ])
        ];
      exposed =
        proto:
        lib.optionals (ep.directAccess.enable && ep.directAccess.interface == "all") [ (localRule proto) ]
        ++ lib.optionals (
          (ep.directAccess.enable && ep.directAccess.interface == "all")
          || ep.directAccess.interface == "wireguard"
          # A named endpoint is reached by an ingress that is a mesh host, even when it never declared
          # direct access for itself: being proxied is what puts it on the mesh, and the rule says so.
          || ep.canonicalDomain != null
        ) (meshRules proto);
    in
    lib.optionals (ep.directAccess.enable || ep.canonicalDomain != null) (lib.concatMap exposed protos)
  ) localEndpointsList;

  # There is no deny rule, and that is the point: the chain's own policy closes what nobody allowed, so
  # "the mesh is judged by who is asking" is expressed by *not opening* a port for the other levels rather
  # than by dropping them afterwards. The previous shape did the opposite - open for everyone, deny on top
  # - which is why the deny needed a shell command at the head of the chain, and why a withdrawn one
  # stayed there forever.

  # Every endpoint that enables directory authentication becomes a consumer with fully resolved values:
  # the audience it stated, the SOPS path its app password lives at, and the DN it binds as. The provider
  # that creates those accounts derives the same DN from the same directory contract, so both sides agree
  # without either reading the other's configuration - they do not even run on the same host, which is
  # exactly why this lives here and not in the provider's feature.
  ldapConsumers = builtins.foldl' (acc: svc: acc // ldapConsumerOf svc) { } (
    builtins.attrNames config.my.contracts.provides
  );

  # A service may expose several endpoints; the first that enables directory authentication decides.
  ldapConsumerOf =
    svc:
    let
      ldapEndpoints = builtins.filter (ep: ep.ldap.enable) (
        builtins.attrValues config.my.contracts.provides.${svc}.endpoints
      );
    in
    if ldapEndpoints == [ ] then
      { }
    else
      let
        ep = builtins.head ldapEndpoints;
        directory = config.my.directory.ldap;
      in
      {
        ${svc}.ldap = {
          inherit (ep.ldap) accessGroups adminGroups;
          secretPath =
            if ep.ldap.secretPath != null then
              ep.ldap.secretPath
            else
              "services/authentik/consumers/${svc}-ldap-password";
          bindDn = "cn=${directory.consumerAccountPrefix}${svc},${directory.usersDn}";
        };
      };

  # --- the portal's declaration is checked at evaluation --------------------------------------------
  # The typed options already reject a wrong type. These assertions catch the value a type cannot see
  # and name the offender, so a bad contract fails `nix flake check` instead of a deploy - the message
  # says which service, field or action to fix.
  portalViolations =
    let
      isSlug = value: builtins.match "[a-z0-9][a-z0-9-]*" value != null;
      startsWithSlash = value: builtins.substring 0 1 value == "/";

      labelViolations =
        where: label:
        lib.optional (!(builtins.hasAttr "de" label)) "${where}: label needs German copy"
        ++ lib.optional (!(builtins.hasAttr "en" label)) "${where}: label needs English copy";

      fieldViolations =
        where: field:
        lib.optional (!isSlug field.id) "${where}: id must be a lowercase slug"
        ++ lib.optional (!startsWithSlash field.pointer) "${where}: pointer must start with '/'"
        ++ labelViolations where field.label;

      listViolations =
        where: list:
        lib.optional (!isSlug list.id) "${where}: id must be a lowercase slug"
        ++ lib.optional (!startsWithSlash list.pointer) "${where}: pointer must start with '/'"
        ++ lib.optional (list.max < 1 || list.max > 10) "${where}: max must be between 1 and 10"
        ++ lib.optional (list.items == [ ]) "${where}: a list needs at least one item field"
        ++ labelViolations where list.label
        ++ lib.concatMap (item: fieldViolations "${where}.items.${item.id}" item) list.items;

      readoutViolations =
        svcName: svc:
        let
          readout = svc.readouts;
          where = "${svcName}.readouts";
        in
        if readout == null then
          [ ]
        else
          lib.optional (readout.read == null && (readout.fields != [ ] || readout.lists != [ ])) (
            "${where}: fields or lists need a read path"
          )
          ++ lib.concatMap (field: fieldViolations "${where}.fields.${field.id}" field) readout.fields
          ++ lib.concatMap (list: listViolations "${where}.lists.${list.id}" list) readout.lists;

      actionViolations =
        svcName: svc:
        lib.concatMap (
          actionId:
          let
            action = svc.actions.${actionId};
            where = "${svcName}.actions.${actionId}";
          in
          lib.optional (!isSlug actionId) "${where}: id must be a lowercase slug"
          ++ lib.optional (!startsWithSlash action.path) "${where}: path must start with '/'"
          ++ lib.optional (
            !(builtins.hasAttr "de" action.confirm)
          ) "${where}: confirm needs a German sentence"
          ++ lib.optional (
            !(builtins.hasAttr "en" action.confirm)
          ) "${where}: confirm needs an English sentence"
          ++ labelViolations where action.label
        ) (builtins.attrNames svc.actions);

      dependsViolations =
        svcName: svc:
        lib.concatMap (
          dependency:
          lib.optional (!isSlug dependency) "${svcName}.dependsOn: '${dependency}' is not a service id"
        ) svc.dependsOn;
    in
    lib.concatLists (
      lib.mapAttrsToList (
        svcName: svc:
        readoutViolations svcName svc ++ actionViolations svcName svc ++ dependsViolations svcName svc
      ) config.my.contracts.provides
    );
in
{
  options.my.portal.locales = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [
      "de"
      "en"
    ];
    description = ''
      Locale tags the portal renders. Contract copy (an endpoint's `dashboard.description`) must carry
      every one of them; the assertion below enforces it, so a locale is never silently missing.
    '';
  };

  options.my.contracts.provides = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          endpoints = lib.mkOption {
            type = lib.types.attrsOf endpointContractSubmodule;
            default = { };
            description = "Network service endpoints exposed by this component";
          };

          # How the portal reads this service and what it may trigger. Beside `endpoints`, not inside an
          # endpoint's `dashboard`, because a contract has one readout and one action set - and because
          # the portal consumes them, not the tile. Omitting `readouts` is the honest "nothing to read".
          readouts = lib.mkOption {
            type = lib.types.nullOr readoutSubmodule;
            default = null;
            description = "What the portal reads from this service at runtime";
          };

          actions = lib.mkOption {
            type = lib.types.attrsOf actionSubmodule;
            default = { };
            description = "Actions the portal may trigger, keyed by their slug";
          };

          # A dependency by service id, not by host: "this one needs that one to work" is a statement
          # about the fleet's shape, and the host that happens to run it must not appear.
          dependsOn = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Other services this one needs to work, named by their ids";
          };
        };
      }
    );
  };

  # Direct Firewall Projection
  config = {
    assertions = [
      {
        assertion = lib.all (
          svc:
          lib.all (
            ep:
            ep.dashboard.description == { }
            || lib.all (locale: builtins.hasAttr locale ep.dashboard.description) config.my.portal.locales
          ) (lib.attrValues svc.endpoints)
        ) (lib.attrValues config.my.contracts.provides);
        message = "an endpoint's dashboard.description must name every locale in my.portal.locales";
      }
      {
        assertion = portalViolations == [ ];
        message = ''
          the portal's readouts, actions or dependencies are invalid:
          ${lib.concatStringsSep "\n" portalViolations}
        '';
      }
    ];

    my.contracts.consumes = ldapConsumers;

    # One firewall, one place: what is opened is derived from the endpoints - already scoped to the
    # interface they name and to the trust levels they are for - and the chain's own policy closes the
    # rest. Nothing here is a command, and nothing has to be withdrawn, because the firewall renders this
    # from the configuration on every activation: the running rules and the declarations cannot disagree.
    networking.firewall.extraInputRules = lib.concatStringsSep "\n" accessRules;
  };
}
