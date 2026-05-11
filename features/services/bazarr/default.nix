{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.features.services.bazarr;
in
{
  options.my.features.services.bazarr = {
    enable = lib.mkEnableOption "Bazarr Subtitle Manager";
    expose = {
      enable = lib.mkEnableOption "Expose via Caddy";
      subdomain = lib.mkOption {
        type = lib.types.str;
        default = "bazarr";
      };
      auth = lib.mkEnableOption "Protect with Authentik" // {
        default = true;
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.bazarr = {
      enable = true;
    };

    # Ensure bazarr has access to the media files
    users.users.bazarr.extraGroups = [ "media" ];

    # Register with Caddy
    my.registry.bazarr = {
      host = config.networking.hostName;
      port = 6767;
      subdomain = if cfg.expose.enable then cfg.expose.subdomain else null;
      auth = cfg.expose.auth;
    };
  };
}
