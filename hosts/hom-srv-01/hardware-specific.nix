_: {
  # The Realtek RTL8761BU dongle on the USB bus is the adapter Home Assistant's Bluetooth
  # integration uses (its config entry names hci0 / 8C:88:4B:45:D3:C5). The kernel driver alone is
  # not enough: Home Assistant speaks to BlueZ over D-Bus, so this host needs the service too.
  my.features.system.bluetooth.enable = true;

  # 4 TB Storage
  fileSystems."/data/storage" = {
    device = "/dev/disk/by-uuid/7874b65e-816d-4377-9a8d-5c58fe2f65ca";
    fsType = "ext4";
    options = [
      "defaults"
      "nofail"
    ];
  };

  # 1 TB Storage (Sekundär)
  fileSystems."/data/storage2" = {
    device = "/dev/disk/by-uuid/ca58fccc-82f4-48bf-a9da-c83874a8b0a9";
    fsType = "ext4";
    options = [
      "defaults"
      "nofail"
    ];
  };
}
