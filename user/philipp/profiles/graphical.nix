# user/philipp/profiles/graphical.nix
# Graphical desktop applications, terminal emulators, and Wayland tools.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ../chrome.nix
    ../rclone-bookmarks.nix
  ];

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
    figma-linux
    figma-agent
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

  # figma-linux ships a desktop entry that never advertises the figma:// scheme, so
  # the browser reports "no application available" and the login handshake cannot
  # return to the app. Shadow it with an entry that registers the handler.
  xdg.desktopEntries.figma-linux = {
    name = "Figma Linux";
    comment = "Unofficial Figma desktop application for Linux";
    exec = "figma-linux %U";
    icon = "figma-linux";
    terminal = false;
    mimeType = [ "x-scheme-handler/figma" ];
  };

  xdg.mimeApps.defaultApplications."x-scheme-handler/figma" = "figma-linux.desktop";

  # figma-agent is socket-activated: the socket starts at login and pulls in the
  # service when Figma connects. Port and unit wiring mirror upstream's
  # files/figma-agent.socket and files/figma-agent.service.
  systemd.user.sockets.figma-agent = {
    Unit.Description = "Figma Agent for Linux Socket";
    Socket.ListenStream = "127.0.0.1:44950";
    Install.WantedBy = [ "sockets.target" ];
  };

  systemd.user.services.figma-agent = {
    Unit = {
      Description = "Figma Agent for Linux Service";
      Requires = [ "figma-agent.socket" ];
    };
    Service = {
      Type = "exec";
      ExecStart = "${pkgs.figma-agent}/bin/figma-agent";
    };
    Install.WantedBy = [ "default.target" ];
  };
}
