{
  config,
  lib,
  ...
}:
let
  cfg = config.my.features.services.jellyseerr;
in
{
  options.my.features.services.jellyseerr = {
    enable = lib.mkEnableOption "Jellyseerr Media Request Manager";
  };

  config = lib.mkIf cfg.enable {
    # Run Jellyseerr as an OCI Container
    virtualisation.oci-containers.containers."jellyseerr" = {
      image = "ghcr.io/v3djg6gl/seerr:feat-oidc-jellyfin-quickconnect";
      extraOptions = [
        "--network=host"
      ];
      volumes = [
        "/var/lib/jellyseerr:/app/config"
      ];
      environment = {
        TZ = "Europe/Berlin";
        NODE_ENV = "production";
      };
    };

    # Ensure the config directory exists with correct permissions recursively
    systemd.tmpfiles.rules = [
      "Z /var/lib/jellyseerr 0750 1000 1000 -"
    ];

    my.contracts.provides.jellyseerr = {
      endpoints.web = {
        port = 5055;
        protocol = "tcp";
        scope = "internal";
        auth = "none";
        subdomain = "seerr";
        dashboard = {
          show = true;
          displayName = "Jellyseerr";
          category = "Media";
          icon = "jellyseerr";
        };
      };
      storage = {
        stateDirs = [ "/var/lib/jellyseerr" ];
      };
    };
  };
}
