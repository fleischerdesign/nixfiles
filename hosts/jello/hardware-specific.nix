{ pkgs, ... }:

{
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver # VAAPI driver for Intel GPUs
      intel-vaapi-driver # Another VAAPI driver
      vpl-gpu-rt # Recommended for Intel Arc GPUs
    ];
  };

  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "iHD";
  };

  hardware.bluetooth = {
    enable = true;
    # Empfohlen für BlueZ-Audio-Verbindungen
    settings = {
      General = {
        Enable = "Source,Sink,Media,Socket";
      };
    };
  };
}
