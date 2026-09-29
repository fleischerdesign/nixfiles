# user/philipp/profiles/graphical.nix
# Graphical desktop applications, terminal emulators, and Wayland tools.
{ pkgs, ... }:
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
      # The window paints its own background translucent; the compositor blurs what shows
      # through. A terminal does not request blur itself, so the registry asks for it.
      background-opacity = 0.8;
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
