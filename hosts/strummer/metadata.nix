# hosts/strummer/metadata.nix
{
  role = "server";
  features = {
    dev.containers.enable = true;
    dev.containers.users = [ "philipp" ];
    services.home-assistant.enable = true;
    services.esphome.enable = true;
    services.mealie.enable = true;
    services.paperless.enable = true;
    services.prowlarr.enable = true;
    services.radarr.enable = true;
    services.sabnzbd.enable = true;
    services.sonarr.enable = true;
    services.cloudflare-dyndns.enable = true;
    services.caddy.enable = true;
    services.authentik.outpost.proxy.enable = true;
    services.authentik.outpost.ldap.enable = true;
  };
}
