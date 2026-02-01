{ config, lib, pkgs, ... }:
let
  cfg = config.my.features.services.jellyseerr;

  # Build Jellyseerr from the OIDC PR branch
  jellyseerr-oidc = pkgs.jellyseerr.overrideAttrs (oldAttrs: {
    pname = "jellyseerr-oidc";
    version = "2.6.0-oidc-preview";

    src = pkgs.fetchFromGitHub {
      owner = "Fallenbagel";
      repo = "jellyseerr";
      rev = "feat/oidc"; # This is the branch with OIDC support
      hash = "sha256-6Indg47u6rhCPvYBTRU3UXFug0D+NmGnZLiyv+jPL4A="; # Temporary hash
    };

    # We need to update the pnpm dependencies hash as well since the branch changed
    pnpmDeps = oldAttrs.pnpmDeps.overrideAttrs (oldDeps: {
      inherit (oldAttrs) pname;
      version = "2.6.0-oidc-preview";
      src = pkgs.fetchFromGitHub {
        owner = "Fallenbagel";
        repo = "jellyseerr";
        rev = "feat/oidc";
        hash = "sha256-6Indg47u6rhCPvYBTRU3UXFug0D+NmGnZLiyv+jPL4A=";
      };
      hash = lib.fakeHash; # Nix will tell us the correct hash
    });
  });
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
    services.jellyseerr = {
      enable = true;
      package = jellyseerr-oidc;
    };

    # Ensure the config directory exists
    systemd.tmpfiles.rules = [
      "d /var/lib/jellyseerr 0750 jellyseerr jellyseerr -"
    ];

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
