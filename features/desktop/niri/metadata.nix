{
  description = "Niri desktop environment";
  features = {
    system.wayland.enable = true;
    system.audio.enable = true;
    desktop.quickshell.enable = true;
  };
  conflicts = {
    desktop.gnome.enable = true;
  };
}