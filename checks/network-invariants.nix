# The promises the network makes, checked against the evaluated fleet. The assertions in the modules
# catch a bad declaration; this catches a fleet whose parts contradict each other - a carried zone
# without a forward rule, a name that answers with an address nothing routes, a client that routes a
# home zone. Every one of them was a real failure before it was a check.
#
# The computation lives in `checks/lib/network-invariants.nix`; this file turns its violations into a
# failing build, which is what makes it a check.
{
  pkgs,
  lib,
  self,
  hostNames,
  ...
}:
let
  result = import ./lib/network-invariants.nix { inherit lib self hostNames; };
in
pkgs.runCommandLocal "network-invariants" { } (
  if result.violations == [ ] then
    "echo 'ok: ${toString (builtins.length result.invariants)} network invariants hold' > $out"
  else
    ''
      cat >&2 <<'VIOLATIONS'
      ${builtins.concatStringsSep "\n" result.violations}
      VIOLATIONS
      exit 1
    ''
)
