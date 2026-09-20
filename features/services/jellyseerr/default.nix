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
        # Public per docs/naming.md §10.4. Seerr authenticates with its own Jellyfin login — exactly
        # like Home Assistant and Jellyfin — so no forward-auth layer and no double login.
        # The image in use is an OIDC-capable fork, but its OIDC configuration contract is not
        # environment based and is undocumented (settings-file based); wiring it declaratively
        # is a separate follow-up, and declaring auth = "oidc" before that would be a lie.
        scope = "public";
        auth = "none";
        publicExempt = "Seerr enforces its own Jellyfin login; an external forward-auth proxy only adds a second login";
        subdomain = "seerr";
        # Ingress reaches this over the WireGuard mesh (invariant I10).
        directAccess = {
          enable = true;
          protocol = "tcp";
          interface = "wireguard";
        };
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
