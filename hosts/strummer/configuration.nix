{
  config,
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ./hardware-specific.nix
    ../../roles/server.nix
  ];

  networking.hostName = "strummer";

  services.caddy = { };

  # Features
  my.features.services.caddy.enable = true;
  my.features.services.caddy.baseDomain = "fls.ancoris.ovh";

  my.features.services.home-assistant.enable = true;
  my.features.services.esphome.enable = true;
  my.features.services.mealie.enable = true;
  my.features.services.paperless.enable = true;
  my.features.services.prowlarr.enable = true;
  my.features.services.radarr.enable = true;
  my.features.services.sabnzbd.enable = true;
  my.features.services.sonarr.enable = true;
  my.features.services.jellyfin.enable = true;
  my.features.services.recyclarr.enable = true;
  my.features.services.blocky.enable = true;
  my.features.services.bazarr.enable = true;
  my.features.services.jellyseerr.enable = true;
  my.features.services.cloudflare-dyndns.enable = true;
  my.features.services.cloudflare-dyndns.domains = [ "fls.ancoris.ovh" ];
  my.features.services.klipper.enable = true;

  # Endpoints (subdomain/auth — set subdomain ≠ null to expose via Caddy)
  my.endpoints.home-assistant.subdomain = "hass";

  my.endpoints.esphome = {
    subdomain = "esphome";
    auth = true;
  };

  my.endpoints.mealie.subdomain = "mealie";

  my.endpoints.paperless.subdomain = "paperless";

  my.endpoints.prowlarr = {
    subdomain = "prowlarr";
    auth = true;
  };

  my.endpoints.radarr = {
    subdomain = "radarr";
    auth = true;
  };

  my.endpoints.sabnzbd = {
    subdomain = "sabnzbd";
    auth = true;
  };

  my.endpoints.sonarr = {
    subdomain = "sonarr";
    auth = true;
  };

  my.endpoints.jellyfin.subdomain = "jellyfin";

  my.endpoints.bazarr = {
    subdomain = "bazarr";
    auth = true;
  };

  my.endpoints.jellyseerr.subdomain = "seerr";

  my.endpoints.mainsail = {
    subdomain = "mainsail";
    auth = true;
  };
  my.endpoints.moonraker = {
    subdomain = "moonraker";
    auth = true;
  };
  my.endpoints.mainsail-cam.subdomain = "cam.moonraker";

  my.features.services.authentik.outpost.proxy.enable = true;
  my.features.services.authentik.outpost.ldap = {
    enable = true;
    coreAddress = "http://${config.my.features.system.networking.topology.hosts.mackaye.tailscaleIp}:9055";
    tokenSecretName = "authentik_outpost_ldap_token_strummer";
  };

  my.features.services.monitoring.node-exporter.enable = true;
  my.features.services.monitoring.alloy = {
    enable = true;
    lokiHost = config.my.features.system.networking.topology.hosts.mackaye.tailscaleIp;
  };
  my.features.services.monitoring.blackbox-exporter.enable = true;

  my.features.system.networking.tailscale.enable = true;
  my.features.system.networking.tailscale.subnetRouter = {
    enable = true;
    routes = [ "192.168.178.0/24" ];
  };

  my.features.services.crowdsec.enable = true;
  my.features.services.crowdsec.role = "agent";

  my.features.system.backups.restic = {
    enable = true;
    environmentFile = "restic_env_strummer";
    paths = [
      "/var/lib"
      "/data/storage/docs"
    ];
    exclude = [
      "**/node_modules"
      "**/.cache"
      "/var/lib/docker"
      "/var/lib/jellyfin/metadata"
    ];
  };

  my.features.dev.nixvim.enable = true;
  my.features.dev.containers.enable = true;
  my.features.dev.containers.users = [ "philipp" ];

  system.stateVersion = "24.11";
}
