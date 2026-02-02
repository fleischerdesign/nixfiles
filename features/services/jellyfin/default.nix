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

      # Native Hardware Acceleration (New in NixOS 24.11/25.05+)
      hardwareAcceleration = {
        enable = true;
        type = "qsv"; # Intel QuickSync - the best choice for your Intel CPU
        device = "/dev/dri/renderD128";
      };

      # Transcoding optimizations
      transcoding = {
        enableHardwareEncoding = true;
        enableIntelLowPowerEncoding = true; # Improves efficiency on newer Intel CPUs
        enableToneMapping = true; # Essential for watching HDR content on non-HDR screens
      };
    };

    # System-level graphics support
    hardware.graphics = {
      enable = true;
      extraPackages = with pkgs; [
        intel-media-driver # Modern Intel driver (Broadwell and newer)
        intel-vaapi-driver # Older Intel driver
        libvdpau-va-gl
      ];
    };

    # Permissions
    users.groups.media = { };
    users.users.jellyfin.extraGroups = [ "media" "video" "render" ];

    # Register with Caddy Feature
    my.features.services.caddy.exposedServices = lib.mkIf cfg.expose.enable {
      "jellyfin" = {
        port = 8096;
        auth = cfg.expose.auth; 
        subdomain = cfg.expose.subdomain;
      };
    };
  };
}
