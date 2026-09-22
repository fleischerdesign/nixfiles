# features/system/networking/firewall/default.nix - one firewall, in one place.
#
# The fleet's whole policy is data, and every part of it is projected into the firewall's own declarative
# options: the endpoints contract opens what services declare, the wireguard module forwards what the
# mesh carries, the gateway module translates and filters what the zones route. None of them writes a
# command, and this module is what makes that possible.
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
    };
  };
}
