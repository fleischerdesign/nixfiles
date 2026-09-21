# contracts/endpoints/default.nix
# Endpoint Contract Specification & Ingress Protocol.
# Defines the typed schema for service network endpoints (ports, scopes, auth policies, OIDC, URLs)
# and projects local direct-access endpoints into host firewall rules.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.contracts;

  # Two things are shared rather than repeated: the firewall's one insertion pattern (head of the chain,
  # guarded against duplication), and the lattice's vocabulary - both come from the modules that own
  # them, so a policy here and the same policy on another chain cannot drift apart.
  firewall = import ../../lib/firewall.nix { inherit lib pkgs; };
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
      };

      # Directory authentication, parallel to `oidc` and on the same axis: `auth` says who gets through
      # the ingress, this says where the application's users come from. LDAP is not an ingress concern
      # - the proxy speaks no LDAP - so it does not belong in the `auth` enum.
      ldap = {
        enable = lib.mkEnableOption "Authenticate this endpoint's users against the Authentik LDAP directory";

        accessGroups = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = ''
            Authentik groups whose members may sign in to this service. Deliberately has no default:
            a service that authenticates against a directory without naming its audience has no
            access policy, and the compiler refuses to build it.
          '';
        };

        adminGroups = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Groups whose members are administrators of this service (usually a subset of accessGroups)";
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

  # Flatten all local endpoints across all declared contracts on this host
  localEndpointsList = lib.concatLists (
    lib.mapAttrsToList (_svcName: contract: lib.attrValues contract.endpoints) cfg.provides
  );

  directEndpoints = lib.filter (ep: ep.directAccess.enable) localEndpointsList;

  allTcp = lib.concatMap (
    ep:
    lib.optional (
      ep.directAccess.interface == "all"
      && (ep.directAccess.protocol == "tcp" || ep.directAccess.protocol == "both")
    ) ep.port
  ) directEndpoints;

  allUdp = lib.concatMap (
    ep:
    lib.optional (
      ep.directAccess.interface == "all"
      && (ep.directAccess.protocol == "udp" || ep.directAccess.protocol == "both")
    ) ep.port
  ) directEndpoints;

  # A named endpoint - one that carries a canonical domain - is proxied by an ingress, and both ingresses
  # (the public one on the ingress host and the local one on the delivery host) reach the serving host over
  # the mesh. So the mesh carries exactly the ports a proxy needs; an endpoint without a name is reached
  # directly or not at all, and has to say so itself.
  proxiedTcp = lib.concatMap (
    ep:
    lib.optional (ep.canonicalDomain != null && (ep.protocol == "tcp" || ep.protocol == "both")) ep.port
  ) localEndpointsList;

  wireguardTcp = lib.unique (
    proxiedTcp
    ++ lib.concatMap (
      ep:
      lib.optional (
        ep.directAccess.interface == "wireguard"
        && (ep.directAccess.protocol == "tcp" || ep.directAccess.protocol == "both")
      ) ep.port
    ) directEndpoints
  );

  wireguardUdp = lib.concatMap (
    ep:
    lib.optional (
      ep.directAccess.interface == "wireguard"
      && (ep.directAccess.protocol == "udp" || ep.directAccess.protocol == "both")
    ) ep.port
  ) directEndpoints;

  # --- the identity policy ---------------------------------------------------------------------------
  # Which address belongs to which trust level is an inventory fact, and it lives in the topology
  # (`sourcesByTrust`): the input policy here, the device policy on the LAN router and whatever policy
  # this repository grows next read one map instead of each deriving its own. The levels come from the
  # same place, because a vocabulary that exists twice is a vocabulary that drifts.
  trustLevels = levels;

  # An endpoint may say which trust levels reach it over the mesh. What is denied there becomes a rule of
  # our own, at a priority *ahead* of the firewall's filter chain, because a port opened for the local
  # network (`interface = "all"`) is otherwise open on every interface - and "the local network is one
  # trusted segment, the mesh is judged by who is asking" is exactly what the trust lattice is for. A
  # drop is final in nftables, so the rule holds no matter what else opens the port; it can only ever
  # restrict, never open, which is why it is safe to derive.
  # An endpoint may say which trust levels reach it over the mesh. What is denied there becomes a rule of
  # our own, at the **head** of the input chain: measured, the firewall accepts a port before anything
  # appended later can speak, so the rule is inserted with `-I INPUT 1` - ahead of every accept - and
  # guarded with `-C`, because `extraCommands` accumulate across activations otherwise (the module's own
  # comment records that lesson from an earlier MASQUERADE rule).
  #
  # The backend in use is the iptables one. The nftables backend rejects the MSS-clamping commands the
  # wireguard module needs (measured: "extraCommands is incompatible with the nftables based firewall"),
  # and it is the only backend that renders the declarative `extraInputRules` - which is why that option
  # had no effect at all when it was tried. A DROP at the head holds whatever else opens the port, so the
  # rule can only ever restrict, never open, and it is safe to derive.
  identityRules = lib.concatMap (
    ep:
    let
      denied = lib.subtractLists ep.directAccess.from trustLevels;
      sources = lib.unique (
        lib.concatMap (level: config.my.topology.sourcesByTrust.${level} or [ ]) denied
      );
      proto = if ep.directAccess.protocol == "udp" then "udp" else "tcp";
      dport = toString ep.port;
      # The rule matches the mesh interface on purpose: the source map now also holds the address a host
      # carries inside its zone, and that address must *not* be judged here - a LAN packet never arrives
      # on wg0, so the rule simply never matches it. One map, one rule, both paths.
      forSource =
        binary: source:
        firewall.guardedInsert {
          inherit binary;
          chain = "INPUT";
          match = "-i wg0 -s ${source} -p ${proto} --dport ${dport} -m comment --comment identity-policy -j DROP";
        };
      v4 = map (forSource "iptables") (lib.filter (address: !(lib.hasInfix ":" address)) sources);
      v6 = map (forSource "ip6tables") (lib.filter (address: lib.hasInfix ":" address) sources);
    in
    lib.optionals (ep.directAccess.enable && denied != [ ]) (v4 ++ v6)
  ) localEndpointsList;
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
in
{
  options.my.contracts.provides = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options.endpoints = lib.mkOption {
          type = lib.types.attrsOf endpointContractSubmodule;
          default = { };
          description = "Network service endpoints exposed by this component";
        };
      }
    );
  };

  # Direct Firewall Projection
  config = {
    my.contracts.consumes = ldapConsumers;

    networking.firewall = {
      allowedTCPPorts = allTcp;
      allowedUDPPorts = allUdp;
      interfaces.wg0 = {
        allowedTCPPorts = wireguardTcp;
        allowedUDPPorts = wireguardUdp;
      };
    };

    # The trust lattice, applied. The rules go into the firewall's own input chain *ahead* of the port
    # accepts, which is what `extraInputRules` is for - a separate nftables table would be a second
    # firewall, and enabling it switches the whole firewall to the nftables implementation, which then
    # rejects the MSS-clamping commands the wireguard module needs (measured). One firewall, one place.
    # The trust lattice, applied at the head of the input path. See `identityRules` for why this is a
    # command rather than a declarative rule: the backend in use ignores the declarative form.
    networking.firewall.extraCommands = lib.concatStringsSep "\n" identityRules;
  };
}
