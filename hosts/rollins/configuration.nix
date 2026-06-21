{ ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./hardware-specific.nix
    ./disk-config.nix
    ../../roles/server.nix
  ];

  networking.hostName = "rollins";

  my.features.services.caddy.enable = true;
  my.features.services.caddy.baseDomain = "rls.ancoris.ovh";

  my.features.system.networking.tailscale.enable = true;
  my.features.system.networking.tailscale.acceptRoutes = true;

  my.features.system.networking.static.enable = true;

  my.features.services.monitoring.node-exporter.enable = true;
  my.features.services.monitoring.alloy = {
    enable = true;
    lokiHost = config.my.features.system.networking.topology.hosts.mackaye.tailscaleIp;
  };
  my.features.services.monitoring.blackbox-exporter.enable = true;

  my.features.services.attic.server.enable = true;

  my.features.services.crowdsec = {
    enable = true;
    role = "agent";
    excludeLogPatterns = [
      ".*cache.*"
      ".*moebius.*"
    ];
  };

  my.features.dev.nixvim.enable = true;

  my.features.services.hermes-agent.enable = true;
  my.features.services.hermes-agent.hostUsers = [ "philipp" ];
  my.features.services.hermes-agent.subdomainDelegation = true;
  services.hermes-agent.settings.platforms.telegram.home_channel = {
    platform = "telegram";
    chat_id = "5838211825";
  };
  services.hermes-agent.container.enable = true;
  services.hermes-agent.container.hostUsers = [ "philipp" ];
  services.hermes-agent.environment = {
    API_SERVER_ENABLED = "true";
    API_SERVER_HOST = "127.0.0.1";
    API_SERVER_PORT = "8642";
  };

  my.features.services.hermes-webui.enable = true;
  my.features.services.authentik.outpost.proxy = {
    enable = true;
    tokenSecretName = "authentik_outpost_proxy_token_rollins";
  };

  my.endpoints.hermes-webui = {
    subdomain = "moebius";
    auth = true;
  };

  my.features.services.camofox.enable = true;

  system.stateVersion = "24.11";
}
