# user/philipp/dsh.nix — dsh (DeepSeek Harness) user configuration for philipp
{ osConfig, lib, ... }:
{
  my.features.dev.dsh.enable = lib.mkDefault (osConfig.my.role != "server");
}
