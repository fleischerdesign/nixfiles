# `nix flake check` evaluates the flake but does not force a host's toplevel: a module that only
# fails when the system is instantiated would be found by a deploy. This forces every host's
# derivation path, so the gate sees what the reconciler would build.
{
  pkgs,
  lib,
  self,
  hostNames,
  ...
}:
pkgs.runCommandLocal "eval-all-hosts" { } (
  lib.concatMapStringsSep "\n" (
    name:
    "echo \"${name}: ${
      builtins.unsafeDiscardStringContext
        self.nixosConfigurations.${name}.config.system.build.toplevel.drvPath
    }\" >> $out"
  ) hostNames
)
