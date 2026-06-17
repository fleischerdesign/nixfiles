{
  config,
  ...
}:
let
  hostTopology = config.my.features.system.networking.topology.hosts.rollins;
in
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

  networking.useDHCP = false;
  networking.interfaces.eth0.useDHCP = false;
  networking.defaultGateway = hostTopology.gateway;
  networking.nameservers = [
    "9.9.9.9"
    "1.1.1.1"
  ];
  networking.interfaces.eth0.ipv4.addresses = [
    {
      address = hostTopology.localIp;
      prefixLength = 24;
    }
  ];

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
    excludeLogPatterns = [ ".*cache.*" ".*moebius.*" ];
  };

  my.features.dev.nixvim.enable = true;

  my.features.services.hermes-agent.enable = true;
  my.features.services.hermes-agent.hostUsers = [ "philipp" ];
  my.features.services.hermes-agent.subdomainDelegation = true;
  services.hermes-agent.settings.platforms.telegram.home_channel = "5838211825";
  services.hermes-agent.container.enable = true;
  services.hermes-agent.container.hostUsers = [ "philipp" ];

  my.features.services.camofox.enable = true;

  system.stateVersion = "24.11";
}
