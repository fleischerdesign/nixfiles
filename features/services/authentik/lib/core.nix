# Where the Authentik core lives, stated once for every consumer that dials it.
#
# The core runs on exactly one host; which one is placement, not a literal. Each outpost and
# the server itself resolve the same hostname through the same predicate, so a moved core
# follows without source edits - and zero or several cores fail loudly instead of dialling
# loopback or list order. The fleet view and the address rule arrive as arguments (injected
# once in mk-system.nix); only feature-owned code is imported relatively.
{
  fleetConfigs,
  addresses,
}:
rec {
  hostName =
    systems:
    fleetConfigs.uniqueHost {
      inherit systems;
      matches = hostCfg: hostCfg.my.features.services.authentik.server.enable or false;
      role = "authentik server";
    };

  # The core's URL as consumerName reaches it: loopback on the core host itself, otherwise the
  # LAN address while both are at home, else the overlay address - always with the port the
  # core actually listens on, never a literal.
  url =
    {
      topology,
      systems,
      consumerName,
    }:
    let
      core = hostName systems;
      port = systems.${core}.config.my.features.services.authentik.server.listenPort;
    in
    if core == consumerName then
      "http://127.0.0.1:${toString port}"
    else
      "http://${
        addresses.serviceAddress {
          inherit topology;
          consumer = topology.hosts.${consumerName} or null;
          peer = topology.hosts.${core};
        }
      }:${toString port}";
}
