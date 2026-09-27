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
      publications."web" = {
        scope = "internal";
        endpoint = "web";
        auth = "authentik";
        accessGroups = [ "media-users" ];
        subdomain = "bazarr";

      };
      presentation.tiles."web" = {
        endpoint = "web";
        description = {
          de = "Untertitel-Verwaltung für Serien und Filme.";
          en = "Subtitle management for shows and movies.";
        };
        show = true;
        displayName = "Bazarr";
        category = "Media";
        icon = "bazarr";
      };
      telemetry.probes."web-http".endpoint = "web";
      telemetry.probes."web-http".kind = "http";
      telemetry.probes."web-http".path = "/ping";
      endpoints.web = {
        port = 6767;
        protocol = "tcp";
      };
      storage = {
        stateDirs = [ "/var/lib/bazarr" ];
        dataDirs = [ ];
        cacheDirs = [ ];
      };
    };
  };
}
