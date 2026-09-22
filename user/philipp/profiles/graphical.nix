# user/philipp/profiles/graphical.nix
# Graphical desktop applications, terminal emulators, and Wayland tools.
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    openclaw
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
    libreoffice-fresh
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
      theme = "Dark Modern";
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
    };
  };
}
