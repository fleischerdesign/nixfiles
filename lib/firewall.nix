# lib/firewall.nix - the one way this repository puts a rule of its own into the firewall's chains.
#
# Three lessons live in here, all of them measured at some point:
#
#   * where a rule goes is part of the rule. An *allow* belongs at the head of its chain (`-I <chain> 1`),
#     because the firewall's own accepts are already there and a rule behind them would never be reached.
#     A *deny* belongs at the tail (`-A <chain>`), because everything that was declared has to have been
#     accepted before it - and because a deny at the head of a chain whose policy is ACCEPT is the only
#     way to close what nobody declared.
#   * every rule is guarded with `-C`, because `extraCommands` are executed on every activation while
#     the ruleset persists: unguarded, the same rule multiplies. The wireguard module records that
#     lesson from an earlier MASQUERADE rule.
#   * a rule of ours can only ever restrict or permit what was declared. Nothing here opens a port that
#     a service or a device did not claim; that is what makes deriving rules from the inventory safe.
{ pkgs, lib }:
{
  # `binary` is iptables or ip6tables: the two address families have separate tools, and a v6 address
  # handed to iptables is an error, not a silent no-op.
  guardedInsert =
    {
      binary,
      chain,
      match,
      position ? "head",
    }:
    let
      where = if position == "tail" then "-A ${chain}" else "-I ${chain} 1";
    in
    "{ ${pkgs.iptables}/bin/${binary} -C ${chain} ${match} 2>/dev/null; } || "
    + "{ ${pkgs.iptables}/bin/${binary} ${where} ${match}; }";

  # The address family a match belongs to, read off its addresses: a consumer that has to split one
  # declaration into v4 and v6 rules can ask instead of guessing.
  familyOf = match: if lib.hasInfix ":" match then "ip6tables" else "iptables";
}
