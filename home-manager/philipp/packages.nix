{ pkgs, inputs, ... }:
{
  home.packages = [
    (pkgs.google-chrome.override {
      commandLineArgs = [
        "--enable-features=VaapiVideoDecodeLinuxGL,VaapiVideoEncoder,Vulkan,VulkanFromANGLE,DefaultANGLEVulkan,VaapiIgnoreDriverChecks,VaapiVideoDecoder,PlatformHEVCDecoderSupport,UseMultiPlaneFormatForHardwareVideo"
      ];
    })
    pkgs.libreoffice
    pkgs.spotify
    pkgs.gnomeExtensions.blur-my-shell
    pkgs.gnomeExtensions.gsconnect
    pkgs.gnomeExtensions.caffeine
    pkgs.gnomeExtensions.dash-to-dock
    # pkgs.gimp
    inputs.figma-linux.packages."x86_64-linux".default
    pkgs.obsidian
    pkgs.orca-slicer
    pkgs.nixd
    pkgs.nixfmt-rfc-style
    pkgs.endeavour
    pkgs.resources
    pkgs.moonlight-qt
    pkgs.packet
    pkgs.freecad-wayland
    pkgs.yaak
    pkgs.penpot-desktop
    pkgs.gemini-cli
    (pkgs.callPackage ../../packages/lychee-slicer { })
    (pkgs.callPackage ../../packages/ficsit { })
  ];

  programs.ghostty = {
    enable = true;
    enableFishIntegration = true;
    settings = {
      theme = "Adwaita Dark";
      font-size = 10;
      keybind = [
        "ctrl+h=goto_split:left"
        "ctrl+l=goto_split:right"
      ];
    };
  };

  programs.vesktop = {
    enable = true;
  };
}
