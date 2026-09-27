# features/desktop/gnome.nix
{
  config,
  lib,
  ...
}:

let
  cfg = config.my.features.desktop.gnome;
in
{
  options.my.features.desktop.gnome = {
    enable = lib.mkEnableOption "GNOME Desktop Environment configuration (dconf settings and extensions)";
  };

  config = lib.mkIf cfg.enable {
    # Dependencies
    my.features.system.wayland.enable = true;
    my.features.system.audio.enable = true;

    # Conflicts
    assertions = [
      {
        assertion = !config.my.features.desktop.niri.enable;
        message = "Gnome cannot be enabled alongside Niri.";
      }
    ];

    home-manager.sharedModules = [ ./home.nix ];
  };
}
