# hosts/strummer/metadata.nix
{
  role = "server";
  features = {
    dev.containers.enable = true;
    dev.containers.users = [ "philipp" ];
    services.home-assistant.enable = true;
    services.esphome.enable = true;
    services.caddy.enable = true;
    services.authentik.proxy.enable = true;
  };
}
