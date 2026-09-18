# features/contracts/default.nix
# Service Contract & Storage Catalog Specification (Clean Architecture & SOLID by Design).
# Declares what services provide (endpoints, storage requirements, health probes, dashboard metadata)
# completely decoupled from host assignment, routing engines, or reverse proxies.
{
  config,
  lib,
  ...
}:

let
  cfg = config.my.contracts;

  # Submodule for Endpoint Contract
  endpointContractSubmodule = lib.types.submodule {
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
        ];
        default = "none";
        description = "Authentication enforcement policy";
      };

      subdomain = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Canonical subdomain prefix (e.g. 'jellyfin' -> jellyfin.vyrx.de)";
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

      healthProbePath = lib.mkOption {
        type = lib.types.str;
        default = "/";
        description = "HTTP path for liveness and health checks";
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
    };
  };

  # Submodule for Storage & Impermanence Contract (ARCHITECTURE.md 8.5)
  storageContractSubmodule = lib.types.submodule {
    options = {
      stateDirs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Machine-generated state directories to persist across ephemeral reboots (/persist/state)";
      };

      dataDirs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Irreplaceable user data directories (/persist/data) - mandatory Tier-3 backup";
      };

      cacheDirs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Ephemeral cache directories (/var/cache) - safe to delete on reboot";
      };

      preBackupHook = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        description = "Idempotent script to dump consistent state before transactional backup";
      };
    };
  };

  # Submodule for Service Contract
  serviceContractSubmodule = lib.types.submodule {
    options = {
      endpoints = lib.mkOption {
        type = lib.types.attrsOf endpointContractSubmodule;
        default = { };
        description = "Network service endpoints exposed by this component";
      };

      storage = lib.mkOption {
        type = storageContractSubmodule;
        default = { };
        description = "Storage persistence and state lifecycle declaration";
      };
    };
  };
in
{
  options.my.contracts = {
    provides = lib.mkOption {
      type = lib.types.attrsOf serviceContractSubmodule;
      default = { };
      description = "Declared service contracts provided by active modules on this host";
    };
  };

  # Multi-Consumer Projections (Open/Closed Principle & Dependency Inversion)
  config = {
    # 1. Project local contracts to legacy my.endpoints for 100% seamless Caddy & Firewall compatibility
    my.endpoints = lib.mkMerge (
      lib.mapAttrsToList (
        svcName: contract:
        lib.mapAttrs' (epName: ep: {
          name = if epName == "default" || epName == "web" then svcName else "${svcName}-${epName}";
          value = {
            host = config.networking.hostName;
            port = ep.port;
            proxy = {
              enable = ep.scope == "public" || ep.scope == "internal";
              subdomain = ep.subdomain;
              auth = ep.auth == "authentik";
              websocket = ep.websocket;
              unauthenticatedPaths = ep.unauthenticatedPaths;
            };
            displayName = ep.dashboard.displayName;
            group = ep.dashboard.category;
            directAccess = {
              enable = ep.scope == "mesh" || ep.scope == "public";
              protocol = ep.protocol;
              interface = if ep.scope == "mesh" then "wireguard" else "all";
            };
            monitoring = {
              http = {
                enable = ep.protocol == "tcp";
                path = ep.healthProbePath;
                group = ep.dashboard.category;
              };
              tcp = {
                enable = true;
                group = ep.dashboard.category;
              };
            };
          };
        }) contract.endpoints
      ) cfg.provides
    );
  };
}
