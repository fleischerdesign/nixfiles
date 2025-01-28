{ lib, pkgs, ... }:
{
  dconf = {
    enable = true;
    settings = {
      "org/gnome/desktop/interface" = {
        enable-hot-corners = true;
        color-scheme = "prefer-dark";
      };

    "org/gnome/desktop/background" = let
      bg = ../../../../media/wallpaper.jpg;
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
        ];
        favorite-apps = [
          "org.gnome.Nautilus.desktop"
          "codium.desktop"
          "spotify.desktop"
          "obsidian.desktop"
          "firefox-beta.desktop"
          "com.raggesilver.BlackBox.desktop"
        ];
      };
      #blur dash-to-dock shell
      "org/gnome/shell/extensions/blur-my-shell/dash-to-dock" = {
        blur = true;
      };

      "org/gnome/shell/extensions/dash-to-dock" = {
        apply-custom-theme = true;
      };
    };
  };
}
