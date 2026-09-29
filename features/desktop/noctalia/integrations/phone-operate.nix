# Phone Operate. Mirroring uses scrcpy; device actions use KDE Connect, whose daemon and
# ports the host enables with programs.kdeconnect, so only the mirroring tool is declared
# here. Pairing a phone is runtime state and is not declared either.
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

    home.packages = [ pkgs.scrcpy ];
  };
}
