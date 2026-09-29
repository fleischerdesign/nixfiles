# user/philipp/profiles/graphical.nix
# Graphical desktop applications, terminal emulators, and Wayland tools.
{ config, pkgs, ... }:
{
  home.packages = with pkgs; [
    telegram-desktop
    google-chrome
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
      # The terminal background follows the one frost level, like every other surface.
      # Only the background is transparent; the text stays opaque.
      background-opacity = config.my.desktop.frostAlpha;
      keybind = [
        "alt+h=goto_split:left"
        "alt+l=goto_split:right"
        "alt+k=goto_split:top"
        "alt+j=goto_split:bottom"
        "ctrl+shift+h=previous_tab"
        "ctrl+shift+l=next_tab"
        "ctrl+shift+t=new_tab"
      ];
    };
  };
}
