# Phone Operate. Mirroring uses scrcpy, device actions use KDE Connect - whose daemon and
# ports the host enables with programs.kdeconnect - and the plugin queries the daemon over
# D-Bus with gdbus. Its manifest also declares android-tools and sshfs. On NixOS each of
# those has to be in the session profile explicitly, because no package brings another's
# PATH along. Pairing a phone is runtime state and is not declared here.
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
      pkgs.android-tools
      pkgs.sshfs
      pkgs.glib.bin
    ];
  };
}
