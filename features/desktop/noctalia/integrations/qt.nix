# Qt applications. The template renders the colour scheme; qt6ct must be told to use it.
# The session environment that makes Qt read qt6ct is set by the Niri adapter, where the
# session's environment is owned.
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
    programs.noctalia.settings.theme.templates.builtin_ids = [ "qt" ];

    home.packages = [ pkgs.qt6Packages.qt6ct ];

    xdg.configFile."qt6ct/qt6ct.conf".text = ''
      [Appearance]
      color_scheme_path=${config.xdg.configHome}/qt6ct/colors/noctalia.conf
      custom_palette=true
      style=Fusion
    '';
  };
}
