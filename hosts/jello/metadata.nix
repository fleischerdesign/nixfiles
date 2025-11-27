# hosts/jello/metadata.nix
{
  role = "desktop";
  features = {
    audio = true;
    common = true;
    bootloader = true;
    kernel = true;
    wayland = true;
    gaming = true;
  };
}
