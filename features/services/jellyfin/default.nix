{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.features.services.jellyfin;
in
{
  options.my.features.services.jellyfin = {
    enable = lib.mkEnableOption "Jellyfin Media Server";
  };

  config = lib.mkIf cfg.enable {
    services.jellyfin = {
      enable = true;

      # Native Hardware Acceleration (New in NixOS 24.11/25.05+)
      hardwareAcceleration = {
        enable = true;
        type = "vaapi"; # Use VAAPI directly instead of QSV to avoid MFX session errors
        device = "/dev/dri/renderD128";
      };

      # Transcoding optimizations
      transcoding = {
        enableHardwareEncoding = true;
        enableIntelLowPowerEncoding = false; # Skylake/Gen9 does not support Low Power encoding
        enableToneMapping = true; # Essential for watching HDR content on non-HDR screens
      };
    };

    # System-level graphics support
    hardware.graphics = {
      enable = true;
      extraPackages = with pkgs; [
        intel-media-driver # Modern Intel driver (Broadwell and newer)
        intel-vaapi-driver # Older Intel driver
        intel-compute-runtime # OpenCL support for Tone Mapping
        libvdpau-va-gl
      ];
    };

    # Permissions
    users.groups.media = { };
    users.users.jellyfin.extraGroups = [
      "media"
      "video"
      "render"
    ];

    my.endpoints.jellyfin = {
      host = config.networking.hostName;
      port = 8096;
    };
  };
}
