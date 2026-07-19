{
  config,
  lib,
  ...
}:
{
  config = {
    networking.firewall.allowedTCPPorts = lib.concatLists (
      lib.mapAttrsToList (
        _: ep: lib.optionals (ep.host == config.networking.hostName && ep.directAccess.enable) [ ep.port ]
      ) config.my.endpoints
    );
  };
}
