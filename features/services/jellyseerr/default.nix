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
        # Public per NAMING.md §10.4. Jellyseerr keeps its own Jellyfin login behind
        # Authentik; its native OIDC login is the alternative to avoid double authentication.
        scope = "public";
        auth = "authentik";
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
