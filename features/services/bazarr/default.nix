{ config, lib, pkgs, ... }:
let
  cfg = config.my.features.services.bazarr;
in
{
  options.my.features.services.bazarr = {
    enable = lib.mkEnableOption "Bazarr Subtitle Manager";
    expose = {
      enable = lib.mkEnableOption "Expose via Caddy";
      subdomain = lib.mkOption { type = lib.types.str; default = "bazarr"; };
      auth = lib.mkEnableOption "Protect with Authentik" // { default = true; };
    };
  };

  config = lib.mkIf cfg.enable {
    services.bazarr = {
      enable = true;
      openFirewall = true;
    };

    # Ensure bazarr has access to the media files
    users.users.bazarr.extraGroups = [ "media" ];

    # Register with Caddy
    my.features.services.caddy.exposedServices = lib.mkIf cfg.expose.enable {
      "bazarr" = {
        port = 6767;
        auth = cfg.expose.auth;
        subdomain = cfg.expose.subdomain;
      };
    };
  };
}
