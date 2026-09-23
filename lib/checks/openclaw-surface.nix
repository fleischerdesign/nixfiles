# lib/checks/openclaw-surface.nix
# The OpenClaw node command grant is a two-sided statement: a node declares which capability
# families it serves, and the gateway it dials decides what it actually grants. The catalogue
# (features/services/openclaw/lib/command-surface.nix) makes both sides derivable, but nothing yet
# proves they agree - so "why is dir.list blocked" stays a runtime question. This check turns it
# into a build failure.
#
# It also fails loudly on the two shapes the projection would otherwise hide: a node that points at
# an address no host in the flake owns, and a node that points at a host with no matching gateway
# instance (a typo in the port).
{
  lib,
  self,
  hostNames,
}:
let
  surface = import ../../features/services/openclaw/lib/command-surface.nix { inherit lib; };

  cfgs = lib.genAttrs hostNames (name: self.nixosConfigurations.${name}.config);

  # The inventory decides: a node names its gateway by address, and the address is the gateway
  # host's overlay address as declared in `my.topology`. Never a literal, never a second list.
  hostByWireguardIp = lib.listToAttrs (
    lib.concatMap (
      host:
      let
        declared = cfgs.${host}.my.topology.hosts.${host} or null;
      in
      lib.optional (declared != null && declared ? wireguardIpv4) {
        name = declared.wireguardIpv4;
        value = host;
      }
    ) hostNames
  );

  entries =
    selector:
    lib.concatMap (
      host:
      lib.mapAttrsToList (instanceName: instance: {
        inherit host instanceName instance;
      }) (selector cfgs.${host})
    ) hostNames;

  nodeEntries = entries (cfg: cfg.my.features.services.openclaw.node.instances or { });
  gatewayEntries = entries (
    cfg:
    lib.filterAttrs (_: instance: instance.enable)
      cfg.my.features.services.openclaw.gateway.instances or { }
  );

  violations = lib.concatMap (
    node:
    let
      gatewayHost = hostByWireguardIp.${node.instance.gateway.host} or null;
      candidates =
        if gatewayHost == null then
          [ ]
        else
          lib.filter (gateway: gateway.instance.port == node.instance.gateway.port) (
            lib.filter (gateway: gateway.host == gatewayHost) gatewayEntries
          );
      label = "${node.host}/${node.instanceName}";
    in
    lib.optional (gatewayHost == null) (
      "openclaw node ${label}: gateway address ${node.instance.gateway.host} belongs to no host in the flake"
    )
    ++ lib.optional (gatewayHost != null && candidates == [ ]) (
      "openclaw node ${label}: no gateway instance on ${gatewayHost} listens on port ${toString node.instance.gateway.port}"
    )
    ++ (
      let
        granted = surface.allowCommands (
          lib.head (map (gateway: gateway.instance.nodePolicy.capabilities) candidates)
        );
        missing = lib.subtractLists granted (surface.allowCommands node.instance.capabilities);
      in
      lib.optional (candidates != [ ] && missing != [ ]) (
        "openclaw node ${label}: its gateway grants no command for ${lib.concatStringsSep ", " missing} (node capabilities ${lib.concatStringsSep ", " node.instance.capabilities})"
      )
    )
  ) nodeEntries;
in
{
  inherit violations;
  inspected = builtins.length nodeEntries;
}
