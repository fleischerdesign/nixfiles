# lib/default.nix
# Central entry point for custom nixfiles library utilities.
{
  home-manager-unstable,
}:

let
  systemBuilder = import ./core/system-builder.nix {
    inherit home-manager-unstable;
  };
in
{
  inherit (systemBuilder) mkSystem;
}
