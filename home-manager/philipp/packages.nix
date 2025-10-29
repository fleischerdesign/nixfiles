{ config, lib, pkgs, inputs, ... }:
{
  config = lib.mkIf config.my.homeManager.packages.enable {
    home.packages = [
      (pkgs.google-chrome.override {
        commandLineArgs = [
          "--enable-features=VaapiVideoDecodeLinuxGL,VaapiVideoEncoder,Vulkan,VulkanFromANGLE,DefaultANGLEVulkan,VaapiIgnoreDriverChecks,VaapiVideoDecoder,PlatformHEVCDecoderSupport,UseMultiPlaneFormatForHardwareVideo"
        ];
      })
      pkgs.nerd-fonts.jetbrains-mono
      # pkgs.gimp
      pkgs.obsidian
      pkgs.orca-slicer
      pkgs.endeavour
      pkgs.resources
      pkgs.moonlight-qt
      pkgs.packet
      pkgs.freecad-wayland
      pkgs.yaak
      pkgs.penpot-desktop
      pkgs.gemini-cli
      pkgs.deskflow
      pkgs.delfin
      pkgs.inkscape
      pkgs.evince
      pkgs.nautilus
      pkgs.gnome-disk-utility
      pkgs.firefox
      (pkgs.callPackage ../../packages/lychee-slicer { })
      (pkgs.callPackage ../../packages/ficsit { })
      (pkgs.callPackage ../../packages/karere { })
    ];

    programs.ghostty = {
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

    programs.vesktop = {
      enable = true;
    };
  };
}
