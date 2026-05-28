{
  lib,
  ...
}:
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

          subdomain = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Subdomain for Caddy reverse proxy (null = no HTTP exposure)";
          };

          fullDomain = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Full domain override (bypasses subdomain + baseDomain resolution)";
          };

          auth = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Protect with Authentik forward-auth";
          };

          caddy = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Let the Caddy feature manage this service's reverse proxy (set false if service handles Caddy itself)";
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
    description = "Central service endpoints — single source of truth for Caddy, monitoring, and future consumers";
  };
}
