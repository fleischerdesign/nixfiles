{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/sda";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "4M";
              type = "EF02"; # BIOS Boot Partition (sda14)
            };
            ESP = {
              size = "106M";
              type = "EF00"; # EFI System (sda15, unused)
              content = {
                type = "filesystem";
                format = "vfat";
              };
            };
            root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/"; # sda1
              };
            };
          };
        };
      };
    };
  };
}
