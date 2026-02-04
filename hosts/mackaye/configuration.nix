{ pkgs, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./hardware-specific.nix
    ./disk-config.nix
  ];

  networking.hostName = "mackaye";

  # Define the user account
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

  # Configure Features
  my.features.services.caddy.baseDomain = "mky.ancoris.ovh";

  # Tailscale (Mesh VPN)
  my.features.system.networking.tailscale.enable = true;

  # Network Configuration (Static IP)
  networking.useDHCP = false;
  networking.interfaces.ens18.useDHCP = false;
  networking.defaultGateway = "37.114.55.1";
  networking.nameservers = [ "1.1.1.1" "8.8.8.8" ];
  networking.interfaces.ens18.ipv4.addresses = [ {
    address = "37.114.55.91";
    prefixLength = 24;
  } ];

  # Monitoring Client
  my.features.services.monitoring.node-exporter.enable = true;
  my.features.services.monitoring.promtail = {
    enable = true;
    lokiHost = "127.0.0.1";
  };

  # CrowdSec Role
  my.features.services.crowdsec.role = "master";

  # Native Authentik
  # my.features.services.authentik.enable = true;

  # State version setting (Initial install)
  system.stateVersion = "24.11"; 
}
