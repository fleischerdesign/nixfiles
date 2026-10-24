# `nix flake check` cannot see a custom output - it warns "unknown flake output" and does not
# evaluate it - so a broken one is invisible until a deploy. This forces the surface the fleet
# deploys through: the `nodTargets` projection must evaluate, and every target must name the
# address it dials.
{
  pkgs,
  lib,
  self,
  ...
}:
let
  targets = self.nodTargets;
  names = lib.attrNames targets;
  withoutAddress = lib.filter (name: (targets.${name}.targetHost or null) == null) names;
in
pkgs.runCommandLocal "output-surfaces" { } (
  if withoutAddress == [ ] then
    "echo 'ok: ${toString (lib.length names)} nodTargets carry an address' > $out"
  else
    ''
      echo "nodTargets without a targetHost: ${lib.concatStringsSep ", " withoutAddress}" >&2
      exit 1
    ''
)
