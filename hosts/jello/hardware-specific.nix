{ pkgs, ... }: {
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

  my.features.system.bluetooth.enable = true;
}
