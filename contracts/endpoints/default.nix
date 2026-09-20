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

  wireguardTcp = lib.concatMap (
    ep:
    lib.optional (
      ep.directAccess.interface == "wireguard"
      && (ep.directAccess.protocol == "tcp" || ep.directAccess.protocol == "both")
    ) ep.port
  ) directEndpoints;

  wireguardUdp = lib.concatMap (
    ep:
    lib.optional (
      ep.directAccess.interface == "wireguard"
      && (ep.directAccess.protocol == "udp" || ep.directAccess.protocol == "both")
    ) ep.port
  ) directEndpoints;
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
    networking.firewall = {
      allowedTCPPorts = allTcp;
      allowedUDPPorts = allUdp;
      interfaces.wg0 = {
        allowedTCPPorts = wireguardTcp;
        allowedUDPPorts = wireguardUdp;
      };
    };
  };
}
