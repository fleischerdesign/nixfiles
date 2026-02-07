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
  home.packages = with pkgs; [
    # --- CLI / Server Safe ---
    gemini-cli
    yazi
  ] ++ lib.optionals (role != "server") [
    # --- Desktop Only ---
    (google-chrome.override {
      commandLineArgs = [
        "--enable-features=VaapiVideoDecodeLinuxGL,VaapiVideoEncoder,VaapiIgnoreDriverChecks,VaapiVideoDecoder,PlatformHEVCDecoderSupport,UseMultiPlaneFormatForHardwareVideo"
      ];
    })
    nerd-fonts.jetbrains-mono
    # gimp
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
    nautilus
    gnome-disk-utility
    bluetuith
    (callPackage ../../packages/lychee-slicer { })
    (callPackage ../../packages/ficsit { })
    (callPackage ../../packages/karere { })
  ];

  programs.ghostty = lib.mkIf (role != "server") {
    enable = true;
    enableFishIntegration = true;
    settings = {
      theme = "Adwaita Dark";
      font-family = "JetBrainsMono Nerd Font";
      font-size = 10;
      keybind = [
        "ctrl+h=goto_split:left"
        "ctrl+l=goto_split:right"
      ];
    };
  };
}