{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.features.services.jellyseerr;
in
{
  options.my.features.services.jellyseerr = {
    enable = lib.mkEnableOption "Jellyseerr Media Request Manager";
    expose = {
      enable = lib.mkEnableOption "Expose via Caddy";
      subdomain = lib.mkOption {
        type = lib.types.str;
        default = "seerr";
      };
      auth = lib.mkEnableOption "Protect with Authentik" // {
        default = false;
      };
    };
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

    my.registry.jellyseerr = {
      host = config.networking.hostName;
      port = 5055;
      subdomain = if cfg.expose.enable then cfg.expose.subdomain else null;
      auth = cfg.expose.auth;
    };
  };
}
