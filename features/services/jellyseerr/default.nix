{ config, lib, pkgs, ... }:
let
  cfg = config.my.features.services.jellyseerr;

  # 1. Pull the Docker image (produces a .tar file)
  jellyseerr-image = pkgs.dockerTools.pullImage {
    imageName = "fallenbagel/jellyseerr";
    imageDigest = "sha256:9f3195998306da6548fc3b2420d114dda64a6e904f41e911168788fb410a7972";
    sha256 = "sha256-6Indg47u6rhCPvYBTRU3UXFug0D+NmGnZLiyv+jPL4A=";
    finalImageTag = "preview-OIDC";
  };

  # 2. Extract the app using 'undocker' instead of 'exportImage' (avoids VM disk space issues)
  jellyseerr-oidc = pkgs.stdenv.mkDerivation {
    pname = "jellyseerr-oidc";
    version = "preview-OIDC";

    src = jellyseerr-image;

    nativeBuildInputs = [ pkgs.undocker pkgs.makeWrapper ];

    unpackPhase = ''
      undocker $src rootfs
    '';

    installPhase = ''
      mkdir -p $out/share/jellyseerr
      # Copy the /app directory from the extracted rootfs (using . to include hidden files)
      if [ -d rootfs/app ]; then
        cp -r rootfs/app/. $out/share/jellyseerr/
      else
        # Fallback in case the structure is slightly different
        cp -r rootfs/. $out/share/jellyseerr/
      fi

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
        ProtectSystem = "full";
        ProtectHome = "true";
        NoNewPrivileges = "true";
      };
    };

    users.users.jellyseerr = {
      isSystemUser = true;
      group = "jellyseerr";
      home = "/var/lib/jellyseerr";
    };
    users.groups.jellyseerr = { };

    my.features.services.caddy.exposedServices = lib.mkIf cfg.expose.enable {
      "jellyseerr" = {
        port = 5055;
        auth = cfg.expose.auth; 
        subdomain = cfg.expose.subdomain;
      };
    };
  };
}
