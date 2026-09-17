{
  config,
  lib,
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

    my.contracts.provides.bazarr = {
      endpoints.web = {
        port = 6767;
        protocol = "tcp";
        scope = "internal";
        auth = "authentik";
        subdomain = "bazarr";
        healthProbePath = "/ping";
        dashboard = {
          show = true;
          displayName = "Bazarr";
          category = "Media";
          icon = "bazarr";
        };
      };
      storage = {
        stateDirs = [ "/var/lib/bazarr" ];
        dataDirs = [ ];
        cacheDirs = [ ];
      };
    };
  };
}
