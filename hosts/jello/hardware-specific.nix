{ pkgs, ... }:
{
  # 1. Z170 PCIe ASPM Power-Fix (verhindert Hängenbleiben bei Sleep/Standby)
  # 2. Intel Arc A770: i915 Treiber (seit Kernel 6.2+ ohne force_probe, auto-detected)
  # 3. i915.enable_dc=0: Deaktiviert Display C-States zur Vermeidung von S3 (deep) Suspend-Freezes
  # 4. CPU Performance: Mitigations abschalten für i7-9700KF (+5-15% IPC)
  boot.kernelParams = [
    "pcie_aspm.policy=performance"
    "i915.enable_dc=0"
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
