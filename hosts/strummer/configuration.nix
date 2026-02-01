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
    extraConfig = ''
      (authentik) {
        reverse_proxy /outpost.goauthentik.io/* 127.0.0.1:9000
        forward_auth 127.0.0.1:9000 {
          uri /outpost.goauthentik.io/auth/caddy
          copy_headers X-Authentik-Username X-Authentik-Groups X-Authentik-Email X-Authentik-Name X-Authentik-Uid X-Authentik-Jwt X-Authentik-Meta-Jwks X-Authentik-Meta-Outpost X-Authentik-Meta-Provider X-Authentik-Meta-App X-Authentik-Meta-Version authorization
          trusted_proxies private_ranges
        }
      }
    '';

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
