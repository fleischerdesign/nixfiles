# features/desktop/gnome.nix
{ config, lib, pkgs, ... }:

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

    home-manager.sharedModules = [{
      dconf = {
        enable = true;
        settings = {
          "org/gnome/desktop/interface" = {
            enable-hot-corners = true;
            color-scheme = "prefer-dark";
          };

          "org/gnome/desktop/background" = let
            # Path to the wallpaper, relative to the flake root.
            bg = ../../media/wallpaper.jpg;
          in {
            picture-uri = "file://${bg}";
            picture-uri-dark = "file://${bg}";
          };

          "org/gnome/shell" = {
            disable-user-extensions = false;
            enabled-extensions = with pkgs.gnomeExtensions; [
              blur-my-shell.extensionUuid
              gsconnect.extensionUuid
              caffeine.extensionUuid
              dash-to-dock.extensionUuid
              pip-on-top.extensionUuid
              paperwm.extensionUuid
            ];
            favorite-apps = [
              "org.gnome.Nautilus.desktop"
              "codium.desktop"
              "spotify.desktop"
              "obsidian.desktop"
              "google-chrome.desktop"
              "com.mitchellh.ghostty.desktop"
            ];
          };
          "org/gnome/shell/extensions/blur-my-shell/dash-to-dock" = {
            blur = true;
          };

          "org/gnome/shell/extensions/dash-to-dock" = {
            apply-custom-theme = true;
            intellihide-mode = "ALL_WINDOWS";
          };

          "org/gnome/shell/extensions/paperwm" = {
            show-focus-mode-icon = false;
            show-open-position-icon = false;
            show-window-position-bar = false;
            show-workspace-indicator = false;
          };
        };
      };
    }];
  };
}