{ pkgs, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./hardware-specific.nix
  ];

  networking.hostName = "strummer";

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

  services.caddy = {
    virtualHosts = {
      "hass.fls.ancoris.ovh".extraConfig = "reverse_proxy 127.0.0.1:8123";
      "esphome.fls.ancoris.ovh".extraConfig = ''
        import authentik
        reverse_proxy 127.0.0.1:6052
      '';
    };
  };

  # State version setting
  system.stateVersion = "24.11"; 

}
