{ pkgs, ... }:
{
  # 1. Z170 PCIe ASPM Power-Fix (verhindert Hängenbleiben bei Sleep/Standby)
  # 2. Intel Arc A770: Wechsel vom alten i915 auf den neuen 'xe' Treiber
  boot.kernelParams = [
    "pcie_aspm.policy=performance"
    "i915.force_probe=!56a0"
    "xe.force_probe=56a0"
  ];

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
