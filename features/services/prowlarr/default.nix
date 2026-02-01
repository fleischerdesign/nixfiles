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
          # Disable internal authentication as we use Authentik Forward Auth
          authenticationmethod = "External";
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