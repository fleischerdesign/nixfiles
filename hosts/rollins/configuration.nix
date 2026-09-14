{ inputs, ... }:
{
  imports = [
    inputs.disko.nixosModules.disko
    ./hardware-configuration.nix
    ./hardware-specific.nix
    ./disk-config.nix
    ../../roles/server.nix
  ];

  networking.hostName = "rollins";

  my.features.services.caddy.baseDomain = "rls.ancoris.ovh";

  my.features.system.networking.tailscale.acceptRoutes = true;

  my.features.services.monitoring = {
    pipeline = {
      enable = true;
      role = "collector";
    };
  };

  my.features.services.attic.server.enable = true;

  my.features.services.crowdsec = {
    enable = true;
    role = "agent";
    excludeLogPatterns = [
      ".*cache.*"
      ".*ai.*"
    ];
  };

  my.features.services.openclaw = {
    enable = true;
    role = "gateway";
    subdomain = "ai";
    auth = true;
    adminUsers = [ "philipp@fleischer.design" ];
  };

  my.features.services.camofox.enable = true;

  my.features.services.authentik.outpost.proxy = {
    enable = true;
    tokenSecretName = "authentik_outpost_proxy_token_rollins";
  };

  sops.secrets."pi/deepseek" = { };
  sops.secrets."pi/openrouter" = { };

  system.stateVersion = "24.11";
}
