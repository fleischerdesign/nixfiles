{ pkgs, ... }:
{
  # 1. Z170 PCIe ASPM Power-Fix (verhindert Hängenbleiben bei Sleep/Standby)
  # 2. Intel Arc A770: Wechsel vom alten i915 auf den neuen 'xe' Treiber
  # 3. CPU Performance: Mitigations abschalten für i7-9700KF (+5-15% IPC)
  boot.kernelParams = [
    "pcie_aspm.policy=performance"
    "i915.force_probe=!56a0"
    "xe.force_probe=56a0"
    "mitigations=off"
  ];

  # Intel P-State Governor auf Höchstleistung (keine 800 MHz Umschaltlatenz)
  powerManagement.cpuFreqGovernor = "performance";

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
