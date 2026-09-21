# features/system/networking/resolver/default.nix - how a host resolves
#
# Every host resolves through the resolver in the inventory, never through whatever a network
# hands it. The resolver has two doors (`features/services/dns`): the home door on the delivery
# point's own address, reached over the home LAN, and the mesh door on its overlay address,
# reached inside WireGuard. Both are read from the inventory - the host that routes the home LAN
# is the host that answers inside it - so no address is written twice.
#
# The component is systemd-resolved, and not by taste: its global server list *is*
# `networking.nameservers` (nixos/modules/system/boot/resolved.nix), it turns openresolv off
# itself while keeping the `resolvconf` compatibility shim, and it tracks which server answers -
# which is what lets a roaming host list two doors and pay one probe, not a timeout per query.
{
  config,
  lib,
  ...
}:
let
  cfg = config.my.features.system.networking.resolver;
  topology = config.my.topology;
  ownHost = topology.hosts.${config.networking.hostName} or null;

  deliveryHost = lib.findFirst (h: (h.lanGateway or [ ]) != [ ]) null (lib.attrValues topology.hosts);
  homeDoor = if deliveryHost == null then null else deliveryHost.ipv4;
  meshDoor = if deliveryHost == null then null else deliveryHost.wireguardIpv4;

  # A host whose zone is a home zone can be at home and then reaches the home door over the LAN;
  # a host in the mesh zone (a cloud host) never can and is served by the mesh door alone.
  mayBeAtHome =
    ownHost != null
    && builtins.elem ownHost.zone [
      "infra"
      "corp"
      "iot"
    ];
  doors = lib.filter (d: d != null) ((if mayBeAtHome then [ homeDoor ] else [ ]) ++ [ meshDoor ]);
in
{
  options.my.features.system.networking.resolver = {
    enable = lib.mkEnableOption "Resolving through the resolver in the inventory (systemd-resolved)";
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = doors != [ ];
        message = "Resolver: no door could be derived (the topology declares no host that routes the home LAN).";
      }
    ];

    # The one place a host learns how to resolve.
    networking.nameservers = doors;

    services.resolved = {
      enable = true;
      settings.Resolve = {
        # systemd-resolved's own default is a public resolver list: a fallback that knows none of
        # our names, and a silent one. Emptying it is what makes "our resolver only" true.
        FallbackDNS = "";
        # All names go to the doors above, so a link's DHCP-provided resolver - a foreign network,
        # the uplink - is never used. A search domain a link provides still completes unqualified
        # names.
        Domains = "~.";
      };
    };

    # NetworkManager feeds the link's DNS into systemd-resolved instead of writing resolv.conf.
    networking.networkmanager.dns = "systemd-resolved";
  };
}
