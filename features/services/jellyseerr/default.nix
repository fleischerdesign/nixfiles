{ config, lib, pkgs, ... }:
let
  cfg = config.my.features.services.jellyseerr;
in
{
  options.my.features.services.jellyseerr = {
    enable = lib.mkEnableOption "Jellyseerr Media Request Manager";
    expose = {
      enable = lib.mkEnableOption "Expose via Caddy";
      subdomain = lib.mkOption { type = lib.types.str; default = "seerr"; };
      auth = lib.mkEnableOption "Protect with Authentik" // { default = false; };
    };
  };

  config = lib.mkIf cfg.enable {
    # Run Jellyseerr as an OCI Container
    virtualisation.oci-containers.containers."jellyseerr" = {
      image = "docker.io/fallenbagel/jellyseerr:preview-OIDC";
      ports = [ "127.0.0.1:5055:5055" ];
      extraOptions = [
        "--add-host=host.containers.internal:host-gateway"
      ];
      volumes = [
        "/var/lib/jellyseerr:/app/config"
      ];
      environment = {
        TZ = "Europe/Berlin";
        NODE_ENV = "production";
      };
    };

    # Ensure the config directory exists with correct permissions
    systemd.tmpfiles.rules = [
      "d /var/lib/jellyseerr 0750 root root -"
    ];

    # Register with Caddy Feature
    my.features.services.caddy.exposedServices = lib.mkIf cfg.expose.enable {
      "jellyseerr" = {
        port = 5055;
        auth = cfg.expose.auth; 
        subdomain = cfg.expose.subdomain;
      };
    };
  };
}