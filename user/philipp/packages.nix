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
      nerd-fonts.jetbrains-mono
      gimp
      bitwarden-desktop
      bitwarden-cli
      obsidian
      orca-slicer
      endeavour
      resources
      moonlight-qt
      packet
      freecad-wayland
      yaak
      penpot-desktop
      deskflow
      delfin
      inkscape
      evince
      libreoffice-fresh
      nautilus
      gnome-disk-utility
      bluetuith
      karere
      (callPackage ../../packages/lychee-slicer { })
      (callPackage ../../packages/ficsit { })
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
