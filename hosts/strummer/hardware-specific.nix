{ ... }:
{
  # 4 TB Storage
  fileSystems."/data/storage" = {
    device = "/dev/disk/by-uuid/7874b65e-816d-4377-9a8d-5c58fe2f65ca";
    fsType = "ext4";
    options = [ "defaults" "nofail" ]; 
  };

  # 1 TB Storage (Sekundär)
  fileSystems."/data/storage2" = {
    device = "/dev/disk/by-uuid/ca58fccc-82f4-48bf-a9da-c83874a8b0a9";
    fsType = "ext4";
    options = [ "defaults" "nofail" ]; 
  };
}
