{
  lib,
  ...
}:
{
  options.my.registry = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { ... }:
        {
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

                conditions = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ "[STATUS] < 500" ];
                };

                interval = lib.mkOption {
                  type = lib.types.str;
                  default = "1m";
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

                conditions = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ "[CONNECTED] == true" ];
                };

                interval = lib.mkOption {
                  type = lib.types.str;
                  default = "1m";
                };
              };
            };
          };
        }
      )
    );

    default = { };
    description = "Central service registry — single source of truth for Caddy, Gatus, and future consumers";
  };
}
