# lib/nftables.nix - how a rule is spelled, so that every projection spells it the same way.
#
# The firewall is declarative: the fleet's policy is data (which trust level may reach which port, which
# device offers what, which zones the router carries) and it is projected into the firewall's own rule
# options. NixOS renders those into one nftables ruleset and applies it atomically, which is what makes
# the properties we depend on true by construction rather than by discipline:
#
#   * a rule whose declaration disappears, disappears - there is no state outside the configuration;
#   * a syntax error cannot reach a running host, because the ruleset is validated as a whole and the
#     check in `checks` lints what we generate before it is ever rendered;
#   * the chain policies decide the defaults (`input` and `forward` are `drop` when filtering is on), so
#     no projection has to write a deny rule to close what nobody declared.
#
# Nothing here is a command: these functions build *matches*, and the modules hand them to
# `networking.firewall.extraInputRules` / `extraForwardRules`, which is where they belong.
{ lib }:
rec {
  # Several addresses go into an nftables set; a single one is spelled bare, because `{ 10.0.0.1 }` is a
  # set of one and reads like a list that was truncated.
  addressSet =
    addresses:
    if lib.length addresses == 1 then
      builtins.head addresses
    else
      "{ ${lib.concatStringsSep ", " addresses} }";

  portSet =
    ports:
    if lib.length ports == 1 then
      toString (builtins.head ports)
    else
      "{ ${lib.concatStringsSep ", " (map toString ports)} }";

  # Composable parts, in the order nftables reads them: match, then verdict.
  rule = parts: lib.concatStringsSep " " (lib.filter (part: part != "") parts);

  # The addresses of the given trust levels, flattened and unique - the one translation from the lattice
  # to addresses, so a policy is written in levels and rendered once.
  sourcesOfTrust =
    topology: levels:
    lib.unique (lib.concatMap (level: topology.sourcesByTrust.${level} or [ ]) levels);
}
