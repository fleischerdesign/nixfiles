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
    # Ensure media group exists
    users.groups.media = { };

    # Explicitly define user to avoid SOPS evaluation issues
    users.users.prowlarr = {
      extraGroups = [ "media" ];
    };

    # SOPS Secret for API Key
    sops.secrets.prowlarr_api_key = { owner = "prowlarr"; };
    sops.templates."prowlarr.env" = {
      owner = "prowlarr";
      content = "PROWLARR__AUTH__APIKEY=${config.sops.placeholder.prowlarr_api_key}";
    };

    services.prowlarr = {
      enable = true;
      environmentFiles = [ config.sops.templates."prowlarr.env".path ];
      settings = {
        auth = {
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
