# contracts/desktop/nixos.nix - the desktop domain's schema.
#
# A host runs at most one desktop environment: each one owns both a session and a display manager,
# and two of them would compete for the same seat. The contract deliberately does *not* list the
# environments it knows. A desktop feature registers itself under `my.desktop.environments` when it
# is enabled, so adding a desktop is one feature plus one host switch - never an edit here. This is
# the same inversion the dependencies contract uses for its consumers and providers.
{ config, lib, ... }:
let
  enabled = lib.attrNames (lib.filterAttrs (_: running: running) config.my.desktop.environments);
in
{
  options.my.desktop.environments = lib.mkOption {
    type = lib.types.attrsOf lib.types.bool;
    default = { };
    description = ''
      Desktop environments this host runs, registered by the desktop features themselves - not an
      operator knob. At most one may be true; the assertion below states that invariant, and there
      is no name list to keep in step with the features.
    '';
  };

  config = {
    assertions = [
      {
        assertion = builtins.length enabled <= 1;
        message = "desktop: one desktop environment per host, but this host enables: ${lib.concatStringsSep ", " enabled}";
      }
    ];
  };
}
