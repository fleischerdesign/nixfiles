{ config, lib, pkgs, ... }:
let
  cfg = config.my.features.services.radarr;
in
{
  options.my.features.services.radarr = {
    enable = lib.mkEnableOption "Radarr Movie Manager";
    expose = {
      enable = lib.mkEnableOption "Expose via Caddy";
      subdomain = lib.mkOption { type = lib.types.str; default = "radarr"; };
      auth = lib.mkEnableOption "Protect with Authentik";
    };
  };

  config = lib.mkIf cfg.enable {
    services.radarr = {
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
      "radarr" = {
        port = 7878;
        auth = cfg.expose.auth;
        subdomain = cfg.expose.subdomain;
      };
    };
  };
}