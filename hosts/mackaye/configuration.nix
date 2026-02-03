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

  # Monitoring Client
  my.features.services.monitoring.node-exporter.enable = true;

  # Native Authentik
  # my.features.services.authentik.enable = true;

  # State version setting (Initial install)
  system.stateVersion = "24.11"; 
}
