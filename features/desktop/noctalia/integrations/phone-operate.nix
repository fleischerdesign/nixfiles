# Phone Operate. Mirroring uses scrcpy and device actions use KDE Connect, so both are the
# plugin's prerequisites; pairing a phone is runtime state and is not declared here.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.features.desktop.noctalia;
in
{
  config = lib.mkIf cfg.enable {
    my.features.desktop.noctalia.settings.plugins.enabled = [ "icefish/phone-operate" ];

    home.packages = [
      pkgs.scrcpy
      pkgs.kdePackages.kdeconnect-kde
    ];
  };
}
