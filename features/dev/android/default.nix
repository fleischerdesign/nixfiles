# features/dev/android.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.my.features.dev.android;
in
{
  options.my.features.dev.android = {
    enable = lib.mkEnableOption "Android Debug Bridge (ADB) tools";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.android-tools ];
  };
}
