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
        # The application and its audience are owned by the reconciler (ADR-039/040); the
        # provider stays declared by the blueprint. Adoption of the existing application is the
        # one explicit step of the migration.
        applicationManagedExternally = true;
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
