# features/android.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.my.features.android;
in
{
  options.my.features.android = {
    enable = lib.mkEnableOption "Android Debug Bridge (ADB) tools";
  };

  config = lib.mkIf cfg.enable {
    programs.adb.enable = true;
  };
}
