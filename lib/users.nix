# One rule for which directories are user identities, shared by the system module that
# creates accounts and the builder that wires Home Manager: two implementations that must
# agree are two chances to disagree about who exists.
{ lib }:
let
  # A user is a directory carrying a metadata file. Anything else in the directory - drafts,
  # notes, a README - is not an account and never becomes one.
  discoverNames =
    dir:
    if builtins.pathExists dir then
      lib.filter (name: builtins.pathExists (dir + "/${name}/metadata.nix")) (
        builtins.attrNames (builtins.readDir dir)
      )
    else
      [ ];

  loadMeta =
    dir: names:
    builtins.listToAttrs (
      map (name: {
        inherit name;
        value = import (dir + "/${name}/metadata.nix");
      }) names
    );
in
{
  inherit discoverNames loadMeta;
}
