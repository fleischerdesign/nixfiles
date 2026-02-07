{ pkgs, inputs, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./hardware-specific.nix
    ../../roles/server.nix
  ];

  networking.hostName = "strummer";

  users.users.philipp = {
    isNormalUser = true;
    description = "Philipp Fleischer";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB+bSErYniJev/+/UxsilaoxHGYW8oVpd3pYMQuuGStw fleis@Yorke"
    ];
  };

  services.caddy = {};

  # Features
  my.features.services.caddy.enable = true;
  my.features.services.caddy.baseDomain = "fls.ancoris.ovh";

  my.features.services.home-assistant.enable = true;
  my.features.services.home-assistant.expose = {
    enable = true;
    subdomain = "hass";
    auth = false;
  };

  my.features.services.esphome.enable = true;
  my.features.services.esphome.expose = {
    enable = true;
    auth = true;
  };

  my.features.services.mealie.enable = true;
  my.features.services.mealie.expose = {
    enable = true;
    auth = false;
  };

  my.features.services.paperless.enable = true;
  my.features.services.paperless.expose.enable = true;

  my.features.services.prowlarr.enable = true;
  my.features.services.prowlarr.expose = {
    enable = true;
    auth = true;
  };

  my.features.services.radarr.enable = true;
  my.features.services.radarr.expose = {
    enable = true;
    auth = true;
  };

  my.features.services.sabnzbd.enable = true;
  my.features.services.sabnzbd.expose = {
    enable = true;
    auth = true;
  };

  my.features.services.sonarr.enable = true;
  my.features.services.sonarr.expose = {
    enable = true;
    auth = true;
  };

  my.features.services.jellyfin.enable = true;
  my.features.services.jellyfin.expose = {
    enable = true;
    subdomain = "jellyfin";
  };

  my.features.services.recyclarr.enable = true;
  my.features.services.blocky.enable = true;
  my.features.services.bazarr.enable = true;
  my.features.services.bazarr.expose.enable = true;
  my.features.services.jellyseerr.enable = true;
  my.features.services.jellyseerr.expose.enable = true;
  my.features.services.cloudflare-dyndns.enable = true;
  my.features.services.cloudflare-dyndns.domains = [ "fls.ancoris.ovh" ];

  my.features.services.authentik.outpost.proxy.enable = true;
  my.features.services.authentik.outpost.ldap = {
    enable = true;
    coreAddress = "http://${config.my.features.system.networking.topology.hosts.mackaye.tailscaleIp}:9055";
    tokenSecretName = "authentik_outpost_ldap_token_strummer";
  };

  my.features.services.monitoring.node-exporter.enable = true;
  my.features.services.monitoring.promtail = {
    enable = true;
    lokiHost = "100.120.39.68";
  };

  my.features.system.networking.tailscale.enable = true;

  my.features.services.crowdsec.enable = true;
  my.features.services.crowdsec.role = "agent";

  my.features.services.klipper.enable = true;
  my.features.services.klipper.expose = {
    enable = true;
    auth = true;
  };

  my.features.dev.nixvim.enable = true;
  my.features.dev.containers.enable = true;
  my.features.dev.containers.users = [ "philipp" ];

  system.stateVersion = "24.11"; 
}