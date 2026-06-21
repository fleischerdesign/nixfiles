# features/system/networking/static/default.nix
{
  config,
  lib,
  ...
}:
let
  cfg = config.my.features.system.networking.static;
  hostName = config.networking.hostName;
  topology = config.my.features.system.networking.topology;
  hostTopology = topology.hosts.${hostName} or null;
in
{
  options.my.features.system.networking.static = {
    enable = lib.mkEnableOption "Static IP setup based on topology";
  };

  config =
    lib.mkIf
      (cfg.enable && hostTopology != null && hostTopology.localIp != null && hostTopology.gateway != null)
      {
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
      };
}
