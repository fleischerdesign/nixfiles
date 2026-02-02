{ config, lib, pkgs, ... }:
let
  cfg = config.my.features.services.jellyfin;
in
{
  options.my.features.services.jellyfin = {
    enable = lib.mkEnableOption "Jellyfin Media Server";
    expose = {
      enable = lib.mkEnableOption "Expose via Caddy";
      subdomain = lib.mkOption { type = lib.types.str; default = "jelly"; };
      auth = lib.mkEnableOption "Protect with Authentik" // { default = false; };
    };
  };

  config = lib.mkIf cfg.enable {
    services.jellyfin = {
      enable = true;
      openFirewall = true;
    };

    # Hardware acceleration for Intel (QuickSync)
    nixpkgs.config.packageOverrides = pkgs: {
      vaapiIntel = pkgs.vaapiIntel.override { enableHybridCodec = true; };
    };
    
    hardware.graphics = {
      enable = true;
      extraPackages = with pkgs; [
        intel-media-driver
        intel-vaapi-driver
        vaapiVdpau
        libvdpau-va-gl
      ];
    };

    # Add jellyfin to media group to read movies and tv shows
    users.groups.media = { };
    users.users.jellyfin.extraGroups = [ "media" "video" "render" ];

    # Register with Caddy Feature
    my.features.services.caddy.exposedServices = lib.mkIf cfg.expose.enable {
      "jellyfin" = {
        port = 8096;
        auth = cfg.expose.auth; # Usually false because Jellyfin has its own auth/OIDC
        subdomain = cfg.expose.subdomain;
      };
    };
  };
}
