{ pkgs, inputs, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./hardware-specific.nix
    ./disk-config.nix
    ../../roles/server.nix
  ];

  networking.hostName = "mackaye";

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

  # Features
  my.features.services.caddy.enable = true;
  my.features.services.caddy.baseDomain = "mky.ancoris.ovh";

  my.features.system.networking.tailscale.enable = true;
  my.features.system.common.geoip.enable = true;

  networking.useDHCP = false;
  networking.interfaces.ens18.useDHCP = false;
  networking.defaultGateway = "37.114.55.1";
  networking.nameservers = [ "1.1.1.1" "8.8.8.8" ];
  networking.interfaces.ens18.ipv4.addresses = [ {
    address = "37.114.55.91";
    prefixLength = 24;
  } ];

  my.features.services.monitoring.node-exporter.enable = true;
  my.features.services.monitoring.promtail = {
    enable = true;
    lokiHost = "127.0.0.1";
  };
  my.features.services.monitoring.prometheus.enable = true;
  my.features.services.monitoring.loki.enable = true;
  my.features.services.monitoring.grafana.enable = true;

  my.features.services.crowdsec.enable = true;
  my.features.services.crowdsec.role = "master";

  my.features.services.postgresql.enable = true;
  my.features.services.redis.enable = true;
  my.features.services.authentik.server.enable = true;
  my.features.services.plausible.enable = true;
  my.features.services.portfolio.enable = true;
  my.features.services.couchdb.enable = true;
  my.features.services.homarr.enable = true;
  my.features.services.vaultwarden.enable = true;
  
  my.features.dev.nixvim.enable = true;

  system.stateVersion = "24.11"; 
}