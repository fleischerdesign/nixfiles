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
      ".*moebius.*"
    ];
  };

  my.features.services.hermes-agent.enable = true;
  my.features.services.hermes-agent.subdomainDelegation = true;
  services.hermes-agent.settings.platforms.telegram.home_channel = {
    platform = "telegram";
    chat_id = "5838211825";
  };
  services.hermes-agent.container.enable = false;
  services.hermes-agent.environment = {
    API_SERVER_ENABLED = "true";
    API_SERVER_HOST = "127.0.0.1";
    API_SERVER_PORT = "8642";
  };

  my.features.services.hermes-webui = {
    enable = true;
    oidcClientId = "WLcmhxTlLrbN9R4e7bfnlSNYi387OW1ynQWu27dG";
    oidcIssuer = "https://auth.ancoris.ovh/application/o/hermes/";
  };

  my.endpoints.hermes-webui = {
    proxy = {
      enable = true;
      subdomain = "moebius";
      auth = false;
    };
  };

  my.features.services.camofox.enable = true;

  system.stateVersion = "24.11";
}
