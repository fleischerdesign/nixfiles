# features/endpoints/default.nix
# Central service endpoints — single source of truth for Caddy, firewall, monitoring, and future consumers.
{
  config,
  lib,
  ...
}:

let
  cfg = config.my.endpoints;

  ownEndpoints = lib.filterAttrs (
    _: ep: ep.host == config.networking.hostName && ep.directAccess.enable
  ) cfg;

  allTcp = lib.concatMap (
    ep:
    lib.optional (
      ep.directAccess.interface == "all"
      && (ep.directAccess.protocol == "tcp" || ep.directAccess.protocol == "both")
    ) ep.port
  ) (lib.attrValues ownEndpoints);

  allUdp = lib.concatMap (
    ep:
    lib.optional (
      ep.directAccess.interface == "all"
      && (ep.directAccess.protocol == "udp" || ep.directAccess.protocol == "both")
    ) ep.port
  ) (lib.attrValues ownEndpoints);

  tailscaleTcp = lib.concatMap (
    ep:
    lib.optional (
      ep.directAccess.interface == "tailscale"
      && (ep.directAccess.protocol == "tcp" || ep.directAccess.protocol == "both")
    ) ep.port
  ) (lib.attrValues ownEndpoints);

  tailscaleUdp = lib.concatMap (
    ep:
    lib.optional (
      ep.directAccess.interface == "tailscale"
      && (ep.directAccess.protocol == "udp" || ep.directAccess.protocol == "both")
    ) ep.port
  ) (lib.attrValues ownEndpoints);

  wireguardTcp = lib.concatMap (
    ep:
    lib.optional (
      ep.directAccess.interface == "wireguard"
      && (ep.directAccess.protocol == "tcp" || ep.directAccess.protocol == "both")
    ) ep.port
  ) (lib.attrValues ownEndpoints);

  wireguardUdp = lib.concatMap (
    ep:
    lib.optional (
      ep.directAccess.interface == "wireguard"
      && (ep.directAccess.protocol == "udp" || ep.directAccess.protocol == "both")
    ) ep.port
  ) (lib.attrValues ownEndpoints);
in
{
  options.my.endpoints = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (submod: {
        options = {
          host = lib.mkOption {
            type = lib.types.str;
            description = "Hostname this service runs on";
          };

          port = lib.mkOption {
            type = lib.types.int;
            description = "Internal port the service listens on";
          };

          proxy = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Expose this service through the Caddy reverse proxy";
            };

            subdomain = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Subdomain for reverse proxy (null = no subdomain)";
            };

            domain = lib.mkOption {
              type = lib.types.str;
              default = config.my.features.services.caddy.baseDomain or "";
              description = "Domain for reverse proxy (defaults to caddy.baseDomain if set)";
            };

            auth = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Protect with Authentik forward-auth";
            };

            websocket = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Enable WebSocket passthrough in reverse proxy";
            };

            # Edge-auth exemptions for machine clients. Both options exist because a single
            # port serves two client classes: browsers (which always send an Origin header)
            # and non-browser clients such as CLIs, nodes, and workers (which do not).
            unauthenticatedPaths = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = ''
                Path globs that bypass forward-auth entirely and are proxied directly.
                Use for self-authenticating routes that carry their own short-lived
                credential in the URL (e.g. "/j/*").
              '';
            };

            machineClientsBypassAuth = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = ''
                Bypass forward-auth for WebSocket upgrades that carry no Origin header,
                i.e. non-browser clients. Browsers always send Origin, so the Control UI
                stays behind forward-auth. Use for services that enforce their own
                credential on the WebSocket handshake (device/bootstrap tokens).
              '';
            };

            customExtraConfig = lib.mkOption {
              type = lib.types.nullOr lib.types.lines;
              default = null;
              description = "Custom Caddyfile directives to prepend/override standard proxy configuration";
            };
          };

          directAccess = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Open this port directly in the firewall (e.g. for native apps, APIs outside Caddy)";
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
                "tailscale"
                "local"
              ];
              default = "all";
              description = "Network interface to bind firewall rule (all, wireguard, tailscale, or local)";
            };
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
              };

              path = lib.mkOption {
                type = lib.types.str;
                default = "/";
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
              };
            };

            scrape = {
              enable = lib.mkEnableOption "Prometheus scrape target for this service";

              port = lib.mkOption {
                type = lib.types.int;
                default = submod.config.port;
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
            default = null;
            description = "Human-readable display name for SSO portals and dashboards (e.g. 'Mainsail (Klipper)')";
          };

          group = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Logical group / category for SSO portals and dashboards (e.g. 'Media', '3D Printing', 'AI & Agents')";
          };

          extraDomains = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Additional domains/aliases associated with this endpoint";
          };

          auth = {
            forward = {
              enable = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Protect this endpoint with Authentik forward-auth outpost";
              };
            };

            oidc = {
              enable = lib.mkEnableOption "Expose endpoint as Authentik OIDC Application";

              clientId = lib.mkOption {
                type = lib.types.str;
                default = submod.config._module.args.name or "app";
                description = "OIDC Client ID";
              };

              clientSecret = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Plaintext client secret (discouraged in favor of clientSecretEnv)";
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
                description = "Relative redirect callback paths (e.g. [ '/login/generic_oauth' ])";
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
          };

          # Computed Read-Only Options
          canonicalDomain = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            readOnly = true;
            description = "The fully resolved FQDN of the service (e.g. grafana.ops.vyrx.de or auth.vyrx.de).";
          };

          publicUrl = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            readOnly = true;
            description = "The public HTTPS URL of the service. Null if proxy is disabled.";
          };

          localUrl = lib.mkOption {
            type = lib.types.str;
            readOnly = true;
            description = "The local loopback HTTP URL used for internal health probes.";
          };
        };

        config = {
          proxy.auth = lib.mkDefault submod.config.auth.forward.enable;

          auth.oidc.redirectUris =
            let
              epConfig = submod.config;
              allDomains =
                (lib.optional (epConfig.canonicalDomain != null) epConfig.canonicalDomain) ++ epConfig.extraDomains;
            in
            lib.mkDefault (
              lib.concatMap (
                domain: map (path: "https://${domain}${path}") epConfig.auth.oidc.redirectPaths
              ) allDomains
            );

          canonicalDomain =
            let
              epConfig = submod.config;
            in
            if !epConfig.proxy.enable then
              null
            else if epConfig.proxy.subdomain != null && epConfig.proxy.subdomain != "" then
              "${epConfig.proxy.subdomain}.${epConfig.proxy.domain}"
            else if epConfig.proxy.domain != null && epConfig.proxy.domain != "" then
              epConfig.proxy.domain
            else
              null;

          publicUrl =
            let
              epConfig = submod.config;
            in
            if epConfig.canonicalDomain != null then "https://${epConfig.canonicalDomain}" else null;

          localUrl =
            let
              epConfig = submod.config;
            in
            "http://127.0.0.1:${toString epConfig.port}";
        };
      })
    );

    default = { };
    description = "Central service endpoints — single source of truth for Caddy, firewall, monitoring, and future consumers";
  };

  config = {
    networking.firewall = {
      allowedTCPPorts = allTcp;
      allowedUDPPorts = allUdp;
      interfaces.tailscale0 = {
        allowedTCPPorts = tailscaleTcp;
        allowedUDPPorts = tailscaleUdp;
      };
      interfaces.wg0 = {
        allowedTCPPorts = wireguardTcp;
        allowedUDPPorts = wireguardUdp;
      };
    };

    assertions = lib.mapAttrsToList (name: ep: {
      assertion = if ep.proxy.enable then ep.canonicalDomain != null else true;
      message = "Endpoint configuration error for service '${name}': proxy is enabled but canonicalDomain resolved to null.";
    }) cfg;
  };
}
