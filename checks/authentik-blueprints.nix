# The identity provider's blueprints only fail on the host: a model name without a dot, a `!KeyOf`
# that points nowhere, a dependency on a blueprint that is not there, or a person who is declared
# instead of seeded. The apply there proves the same files, but a deploy is too late for a typo. This
# reads the exact compiled directory the server ships, so the check and the apply consume identical
# bytes. The rules are documented in docs/identity.md §5 and enforced by
# features/services/authentik/lib/blueprints-check.py.
{
  pkgs,
  lib,
  self,
  blueprintHosts,
  ...
}:
let
  blueprintLib = import ../features/services/authentik/lib/blueprint.nix {
    inherit lib;
  };
  directories = map (
    name: self.nixosConfigurations.${name}.config.my.features.services.authentik.server.blueprintsDir
  ) blueprintHosts;
  ownerLabel = "${blueprintLib.ownerLabelName}=${blueprintLib.ownerLabelValue}";
in
pkgs.runCommandLocal "authentik-blueprints-check"
  {
    nativeBuildInputs = [
      (pkgs.python3.withPackages (pythonPackages: [ pythonPackages.pyyaml ]))
    ];
  }
  ''
    python3 ${../features/services/authentik/lib/blueprints-check.py} \
      --owner-label ${lib.escapeShellArg ownerLabel} \
      ${lib.concatStringsSep " " (map (directory: lib.escapeShellArg "${directory}") directories)} \
      > $out
  ''
