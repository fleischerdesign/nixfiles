# features/desktop/anytype/home.nix - the per-user half of the Anytype feature.
{ pkgs, ... }:
{
  home.packages = [ pkgs.anytype ];
}
