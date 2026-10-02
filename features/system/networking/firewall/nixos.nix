# features/system/networking/firewall/nixos.nix - one firewall, in one place.
#
# The fleet's whole policy is data, and every part of it is projected into the firewall's own declarative
# options: the endpoints contract declares what a service offers, this module turns that declaration into
# the input rules, the wireguard module forwards what the mesh carries, the gateway module translates and
# filters what the zones route. None of them writes a command, and this module is what makes that possible.
#
# Two settings live here, and both are decisions rather than details:
#
#   * the **nftables implementation**, which renders one ruleset from all of the declarations above and
#     applies it atomically. The previous implementation put shell `iptables` commands into
#     `extraCommands` - measured, that cost us twice: a syntax error stopped the firewall mid-reload and
#     took the NAT for a whole zone with it, and a rule whose declaration was withdrawn stayed in the
#     chain forever (28535 dropped packets against a rule that no longer existed in the configuration).
#   * **filtering for forwarded traffic**. Its default is `false`, which leaves IP forwarding
#     unfiltered: with the iptables implementation the forward chain's policy was ACCEPT, so the
#     allow-list this repository derives was decoration - every mesh member reached every device on every
#     port until `filterForward` was turned on and the chain's own policy became `drop`.
{
  config,
  lib,
  ...
}:
let
  cfg = config.my.features.system.networking.firewall;

  nftRender = import ../lib/nftables-render.nix { inherit lib; };
  accessSources = import ../../../../contracts/topology/lib/access-sources.nix { inherit lib; };

  # --- what the declared endpoints open -------------------------------------------------------------
  # The contracts say what a service offers and to whom; this is where that becomes a rule. Two things
  # are being said, and one port list cannot say both: a port opened for the local network is reachable
  # from every address on it - that is what "the local network is one trusted segment" means - while the
  # mesh is judged by who is asking, which is the trust lattice, written in levels and rendered into
  # addresses here.
  #
  # Every rule is an allow. Under the nftables implementation they land in the firewall's `input-allow`
  # chain *behind* the declarative port accepts, so a deny here would never be reached - and it is not
  # needed, because the chain's own policy is `drop`: what nobody allowed is closed. The previous shape
  # opened a port for everyone and denied the mesh levels on top, which is why the deny had to be inserted
  # at the head of the chain with a shell command, and why a withdrawn one stayed there forever.
  #
  # A named endpoint is proxied by an ingress, and the ingress is a host of the `mesh` zone: a proxy always
  # implies that level, whatever the endpoint declares for direct use. That is also why the mesh side is
  # narrower than it used to be - it is no longer "every mesh member", but the levels the endpoint is for.
  allTrustLevels = config.my.topology.trustLevels;

  # The mesh interface name is owned by the WireGuard feature; the rules below read it rather than
  # spelling it. A renamed tunnel keeps its rules, and a name nobody configured cannot drift apart
  # from the interface the kernel actually creates.
  meshInterface = config.my.features.system.networking.wireguard.interfaceName;

  localEndpointsList = lib.concatLists (
    lib.mapAttrsToList (
      _svcName: contract:
      lib.mapAttrsToList (epName: ep: {
        inherit ep;
        # Being referenced by a named publication is what puts an endpoint behind the ingress, and the
        # ingress is a mesh host - so a proxied listener is reachable over the mesh whether or not it
        # declared direct access for itself.
        proxied = lib.any (pub: pub.endpoint == epName && pub.canonicalDomain != null) (
          lib.attrValues contract.publications
        );
      }) contract.endpoints
    ) config.my.contracts.provides
  );

  accessRules = lib.concatMap (
    item:
    let
      ep = item.ep;
      protos =
        if ep.directAccess.protocol == "both" then
          [
            "tcp"
            "udp"
          ]
        else
          [ ep.directAccess.protocol ];
      # An empty `from` means every declared trust level; a publication additionally implies `mesh`.
      declaredLevels =
        if !ep.directAccess.enable then
          [ ]
        else if ep.directAccess.from == [ ] && ep.directAccess.fromHosts == [ ] then
          allTrustLevels
        else
          ep.directAccess.from;
      meshSources = lib.unique (
        accessSources.sourcesOfTrust config.my.topology declaredLevels
        ++ accessSources.sourcesOfHosts config.my.topology (
          ep.directAccess.fromHosts ++ lib.optional item.proxied config.my.topology.ingressHost
        )
      );
      v4 = lib.filter (address: !(lib.hasInfix ":" address)) meshSources;
      v6 = lib.filter (address: lib.hasInfix ":" address) meshSources;
      dport = toString ep.port;
      localRule =
        proto:
        nftRender.rule [
          ''iifname != "${meshInterface}"''
          "${proto} dport ${dport}"
          "accept"
        ];
      meshRules =
        proto:
        lib.optionals (v4 != [ ]) [
          (nftRender.rule [
            ''iifname "${meshInterface}"''
            "ip saddr ${nftRender.addressSet v4}"
            "${proto} dport ${dport}"
            "accept"
          ])
        ]
        ++ lib.optionals (v6 != [ ]) [
          (nftRender.rule [
            ''iifname "${meshInterface}"''
            "ip6 saddr ${nftRender.addressSet v6}"
            "${proto} dport ${dport}"
            "accept"
          ])
        ];
      exposed =
        proto:
        lib.optionals (ep.directAccess.enable && ep.directAccess.interface == "all") [ (localRule proto) ]
        ++ lib.optionals (
          (ep.directAccess.enable && ep.directAccess.interface == "all")
          || ep.directAccess.interface == "wireguard"
          || item.proxied
        ) (meshRules proto);
    in
    lib.optionals (ep.directAccess.enable || item.proxied) (lib.concatMap exposed protos)
  ) localEndpointsList;

  # There is no deny rule, and that is the point: the chain's own policy closes what nobody allowed, so
  # "the mesh is judged by who is asking" is expressed by *not opening* a port for the other levels rather
  # than by dropping them afterwards. The previous shape did the opposite - open for everyone, deny on top
  # - which is why the deny needed a shell command at the head of the chain, and why a withdrawn one
  # stayed there forever.
in
{
  options.my.features.system.networking.firewall = {
    enable = lib.mkEnableOption "the nftables-based fleet firewall";
  };

  config = lib.mkIf cfg.enable {
    # `networking.firewall` then uses its nftables implementation, and `extraInputRules` /
    # `extraForwardRules` are rendered - the declarative options that were inert under the old backend.
    networking.nftables.enable = true;

    networking.firewall = {
      enable = true;
      # The forward chain's policy becomes `drop`; everything allowed through it is declared by the
      # modules that carry zones and devices. Without this line every allow-list is decoration.
      filterForward = true;

      # One firewall, one place: what is opened is derived from the endpoints - already scoped to the
      # interface they name and to the trust levels they are for - and the chain's own policy closes the
      # rest. Nothing here is a command, and nothing has to be withdrawn, because the firewall renders
      # this from the configuration on every activation.
      extraInputRules = lib.concatStringsSep "\n" accessRules;
    };
  };
}
