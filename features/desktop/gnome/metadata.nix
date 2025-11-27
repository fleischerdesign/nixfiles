{
  description = "GNOME Desktop Environment configuration (dconf settings and extensions)";
  features = {
    system.wayland.enable = true;
    system.audio.enable = true;
  };
  conflicts = {
    desktop.niri.enable = true;
  };
}