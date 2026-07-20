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
    lib.optional
      (ep.directAccess.interface == "all" && (ep.directAccess.protocol == "tcp" || ep.directAccess.protocol == "both"))
      ep.port
  ) (lib.attrValues ownEndpoints);

  allUdp = lib.concatMap (
    ep:
    lib.optional
      (ep.directAccess.interface == "all" && (ep.directAccess.protocol == "udp" || ep.directAccess.protocol == "both"))
      ep.port
  ) (lib.attrValues ownEndpoints);

  tailscaleTcp = lib.concatMap (
    ep:
    lib.optional
      (
        ep.directAccess.interface == "tailscale"
        && (ep.directAccess.protocol == "tcp" || ep.directAccess.protocol == "both")
      )
      ep.port
  ) (lib.attrValues ownEndpoints);

  tailscaleUdp = lib.concatMap (
    ep:
    lib.optional
      (
        ep.directAccess.interface == "tailscale"
        && (ep.directAccess.protocol == "udp" || ep.directAccess.protocol == "both")
      )
      ep.port
  ) (lib.attrValues ownEndpoints);
in
{
  options.my.endpoints = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (_: {
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
                "tailscale"
                "local"
              ];
              default = "all";
              description = "Network interface to bind firewall rule (all, tailscale, or local)";
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
                description = "Port to scrape Prometheus metrics from (may differ from service port)";
              };

              path = lib.mkOption {
                type = lib.types.str;
                default = "/metrics";
                description = "Metrics endpoint path";
              };
            };
          };
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
    };
  };
}
