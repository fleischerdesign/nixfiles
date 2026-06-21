# features/system/bluetooth/default.nix
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.my.features.system.bluetooth;
in {
  options.my.features.system.bluetooth = {
    enable = lib.mkEnableOption "Bluetooth support with audio optimizations";
  };

  config = lib.mkIf cfg.enable {
    hardware.bluetooth = {
      enable = true;
      powerOnBoot = lib.mkDefault true;
      # Recommended settings for BlueZ audio connections
      settings = {
        General = {
          Enable = "Source,Sink,Media,Socket";
        };
      };
    };
  };
}
