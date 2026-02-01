{ config, lib, pkgs, ... }:
let
  cfg = config.my.features.services.prowlarr;
in
{
  options.my.features.services.prowlarr = {
    enable = lib.mkEnableOption "Prowlarr Indexer Manager";
    expose = {
      enable = lib.mkEnableOption "Expose via Caddy";
      subdomain = lib.mkOption { type = lib.types.str; default = "prowlarr"; };
      auth = lib.mkEnableOption "Protect with Authentik";
    };
  };

  config = lib.mkIf cfg.enable {
    services.prowlarr = {
      enable = true;
      settings = {
        auth = {
          # Correct internal property name for environment variable override
          method = "External";
        };
      };
    };

    # Register with Caddy Feature
    my.features.services.caddy.exposedServices = lib.mkIf cfg.expose.enable {
      "prowlarr" = {
        port = 9696;
        auth = cfg.expose.auth;
        subdomain = cfg.expose.subdomain;
      };
    };
  };
}
