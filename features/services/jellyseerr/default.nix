{ config, lib, pkgs, ... }:
let
  cfg = config.my.features.services.jellyseerr;

  # 1. Pull the Docker image with the OIDC PR
  jellyseerr-image = pkgs.dockerTools.pullImage {
    imageName = "fallenbagel/jellyseerr";
    imageDigest = "sha256:9f3195998306da6548fc3b2420d114dda64a6e904f41e911168788fb410a7972";
    sha256 = "sha256-6Indg47u6rhCPvYBTRU3UXFug0D+NmGnZLiyv+jPL4A=";
    finalImageTag = "preview-OIDC";
  };

  # 2. Export the image to a flat tarball of the rootfs
  jellyseerr-rootfs = pkgs.dockerTools.exportImage {
    fromImage = jellyseerr-image;
  };

  # 3. Extract the app from the rootfs and wrap it
  jellyseerr-oidc = pkgs.stdenv.mkDerivation {
    pname = "jellyseerr-oidc";
    version = "preview-OIDC";

    src = jellyseerr-rootfs;

    nativeBuildInputs = [ pkgs.makeWrapper ];

    unpackPhase = ''
      mkdir rootfs
      tar -xf $src -C rootfs
    '';

    installPhase = ''
      mkdir -p $out/share/jellyseerr
      # Copy the /app directory from the image rootfs
      cp -r rootfs/app/* $out/share/jellyseerr/

      mkdir -p $out/bin
      makeWrapper ${pkgs.nodejs_22}/bin/node $out/bin/jellyseerr \
        --add-flags "$out/share/jellyseerr/dist/index.js" \
        --chdir "$out/share/jellyseerr" \
        --set NODE_ENV production \
        --set CONFIG_DIRECTORY /var/lib/jellyseerr
    '';
  };
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
    # Systemd service for Jellyseerr
    systemd.services.jellyseerr = {
      description = "Jellyseerr Media Request Manager (OIDC Preview)";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        ExecStart = "${jellyseerr-oidc}/bin/jellyseerr";
        User = "jellyseerr";
        Group = "jellyseerr";
        StateDirectory = "jellyseerr";
        Restart = "always";
        
        # Hardening
        ProtectSystem = "full";
        ProtectHome = "true";
        NoNewPrivileges = "true";
      };
    };

    # Define user and group
    users.users.jellyseerr = {
      isSystemUser = true;
      group = "jellyseerr";
      home = "/var/lib/jellyseerr";
    };
    users.groups.jellyseerr = { };

    # Register with Caddy
    my.features.services.caddy.exposedServices = lib.mkIf cfg.expose.enable {
      "jellyseerr" = {
        port = 5055;
        auth = cfg.expose.auth; 
        subdomain = cfg.expose.subdomain;
      };
    };
  };
}