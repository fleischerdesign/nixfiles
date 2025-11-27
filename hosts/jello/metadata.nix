# hosts/jello/metadata.nix
{
  role = "desktop";
  features = {
    gaming = true;
    spotify = true;
    containers = { enable = true; users = [ "philipp" ]; };
    android = true;
    codium = true;
    niri = true;
  };
}
