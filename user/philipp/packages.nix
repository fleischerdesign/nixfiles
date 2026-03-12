{
  config,
  lib,
  pkgs,
  inputs,
  osConfig,
  ...
}:
let
  role = osConfig.my.role;
in
{
  home.packages =
    with pkgs;
    [
      # --- CLI / Server Safe ---
      gemini-cli
      yazi
    ]
    ++ lib.optionals (role != "server") [
      # --- Desktop Only ---
      opencode
      google-chrome
      nerd-fonts.jetbrains-mono
      gimp
      obsidian
      orca-slicer
      resources
      moonlight-qt
      packet
      yaak
      penpot-desktop
      delfin
      inkscape
      evince
      libreoffice-fresh
      nautilus
      gnome-disk-utility
      bluetuith
      karere
      cameractrls-gtk4
      (callPackage ../../packages/lychee-slicer { })
    ];

  programs.ghostty = lib.mkIf (role != "server") {
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
