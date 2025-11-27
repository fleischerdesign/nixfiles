# hosts/yorke/metadata.nix
{
  role = "notebook";
  features = {
    desktop.niri.enable = true;
    desktop.quickshell.enable = true;

    dev.containers.enable = true;
    dev.containers.users = [ "philipp" ];
    dev.android.enable = true;
    dev.codium.enable = true;
    dev.nixvim.enable = true;

    media.spotify.enable = true;
  };
}
