# hosts/jello/metadata.nix
{
  role = "desktop";
  features = {
    media.gaming.enable = true;
    media.spotify.enable = true;

    dev.containers.enable = true;
    dev.containers.users = [ "philipp" ];
    dev.android.enable = true;
    dev.codium.enable = true;
    dev.nixvim.enable = true;
    desktop.niri.enable = true;
  };
}
