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
  };

  config = lib.mkIf cfg.enable {
    services.bazarr = {
      enable = true;
    };

    # Ensure bazarr has access to the media files
    users.users.bazarr.extraGroups = [ "media" ];

    my.endpoints.bazarr = {
      host = config.networking.hostName;
      port = 6767;
    };
  };
}
