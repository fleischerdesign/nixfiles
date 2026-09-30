# user/philipp/profiles/graphical.nix
# Graphical desktop applications, terminal emulators, and Wayland tools.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [ ../chrome.nix ];

  home.packages = with pkgs; [
    telegram-desktop
    nerd-fonts.jetbrains-mono
    gimp
    obsidian
    orca-slicer
    lycheeslicer
    resources
    moonlight-qt
    packet
    yaak
    jellyfin-desktop
    inkscape
    evince
    libreoffice
    nautilus
    gnome-disk-utility
    bluetuith
    custom.karere
    cameractrls-gtk4
    dbeaver-bin
  ];

  programs.ghostty = {
    enable = true;
    enableFishIntegration = true;
    settings = {
      font-family = "JetBrainsMono Nerd Font";
      font-size = 10;
      keybind = [
        "alt+h=goto_split:left"
        "alt+l=goto_split:right"
        "alt+k=goto_split:top"
        "alt+j=goto_split:bottom"
        "ctrl+shift+h=previous_tab"
        "ctrl+shift+l=next_tab"
        "ctrl+shift+t=new_tab"
      ];
    }
    # Written only when there is something to frost: the terminal background follows the
    # one transparency value, and only the background - the text stays opaque.
    // lib.optionalAttrs (config.my.desktop.surfaceOpacity < 1.0) {
      background-opacity = config.my.desktop.surfaceOpacity;
    };
  };
}
