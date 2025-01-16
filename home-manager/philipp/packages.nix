{ pkgs, ... }:
{
  home.packages = [
    (pkgs.google-chrome.override {
      commandLineArgs = [ "--enable-features=VaapiVideoDecodeLinuxGL,VaapiVideoEncoder,Vulkan,VulkanFromANGLE,DefaultANGLEVulkan,VaapiIgnoreDriverChecks,VaapiVideoDecoder,PlatformHEVCDecoderSupport,UseMultiPlaneFormatForHardwareVideo" ];
    })
    pkgs.spotify
    pkgs.gnomeExtensions.blur-my-shell
    pkgs.gnomeExtensions.gsconnect
    pkgs.gnomeExtensions.caffeine
    pkgs.gnomeExtensions.dash-to-dock
    pkgs.gimp
    pkgs.blackbox-terminal
    pkgs.figma-linux
    pkgs.obsidian
    pkgs.orca-slicer
    pkgs.nixd
    pkgs.nixfmt-rfc-style
    pkgs.endeavour
    pkgs.resources
    (pkgs.callPackage ../../packages/lychee-slicer { })
    (pkgs.callPackage ../../packages/ficsit { })
  ];
}