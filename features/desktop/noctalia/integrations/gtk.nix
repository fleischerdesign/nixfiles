# GTK 3/4 applications. The templates render the CSS and import it into the writable
# gtk.css; `adw-gtk3` is the theme they select, and without it the import alone applies.
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
    programs.noctalia.settings.theme.templates.builtin_ids = [
      "gtk3"
      "gtk4"
    ];

    home.packages = [ pkgs.adw-gtk3 ];
  };
}
