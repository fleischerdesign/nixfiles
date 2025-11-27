# hosts/yorke/metadata.nix
{
  role = "desktop"; # This will be processed by our custom logic
  features = {
    audio = true;
    niri = true;
    bootloader = true;
    containers = { enable = true; users = [ "philipp" ]; };
    android = true;
    common = true;
    kernel = true;
    wayland = true;
    fish-shell = true;
    printing = true;
    spotify = true;
    codium = true;
    nixvim = true;
    quickshell = true;
  };
}
