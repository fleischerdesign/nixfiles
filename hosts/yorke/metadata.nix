# hosts/yorke/metadata.nix
{
  role = "notebook";
  features = {
    niri = true;
    containers = { enable = true; users = [ "philipp" ]; };
    android = true;
    spotify = true;
    codium = true;
    nixvim = true;
    quickshell = true;
  };
}
