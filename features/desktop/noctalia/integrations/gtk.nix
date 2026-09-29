# GTK 3/4 applications. The built-in templates render the colours and import them into the
# writable gtk.css; this module adds a second import so the windows themselves can be
# translucent, and the compositor blurs what shows through. `adw-gtk3` is the theme they
# select. gtk.css is written at runtime, so it has to be a template too, not a Home Manager
# file - otherwise the template's own hook would replace it.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.features.desktop.noctalia;

  # Only the background is affected; text and widgets stay opaque. The alpha is the one
  # session transparency value, so GTK applications follow it like every other surface.
  frostCss =
    if config.my.desktop.surfaceOpacity >= 1.0 then
      "/* No frosted surface at this transparency value. */"
    else
      ''
        window,
        .background,
        headerbar {
          background-color: alpha(@window_bg_color, ${toString config.my.desktop.surfaceOpacity}) !important;
          background-image: none !important;
        }
      '';
in
{
  config = lib.mkIf cfg.enable {
    my.features.desktop.noctalia.settings.theme.templates = {
      builtin_ids = [
        "gtk3"
        "gtk4"
      ];
      # Both imports have to sit at the top of gtk.css, which is why the file is rendered as a
      # template: Noctalia's own hook then finds its import already present and leaves it alone.
      user = {
        gtk3_imports = {
          input_path = "${../templates/gtk-imports.css}";
          output_path = "$XDG_CONFIG_HOME/gtk-3.0/gtk.css";
        };
        gtk4_imports = {
          input_path = "${../templates/gtk-imports.css}";
          output_path = "$XDG_CONFIG_HOME/gtk-4.0/gtk.css";
        };
      };
    };

    xdg.configFile = {
      "gtk-3.0/frost.css".text = frostCss;
      "gtk-4.0/frost.css".text = frostCss;
    };

    home.packages = [ pkgs.adw-gtk3 ];
  };
}
