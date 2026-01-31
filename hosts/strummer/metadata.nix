# hosts/strummer/metadata.nix
{
  role = "server";
  features = {
    dev.containers.enable = true;
    dev.containers.users = [ "philipp" ];
  };
}
