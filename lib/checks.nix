# Check discovery: one file per check, the file name is the output name.
#
# The same rule as `lib/discovery.nix` for modules, applied to the check surface: a check is a file,
# not an entry in a list. `checks/<name>.nix` and `checks/integration/<name>.nix` are functions
# `checkArgs -> derivation`; adding one is adding a file, and no manifest can drift out of date.
#
# `lib/` is the one reserved subdirectory: it holds the values a check computes before wrapping them
# in a derivation. Fixture trees are `.nix`-less directories next to the check that reads them
# (`fixtures/`), and a directory that holds a `.nix` file is a mistake, not something to skip quietly
# - the same reasoning that made `nixos.nix` the module marker.
{ lib }:
let
  reserved = [ "lib" ];

  discover =
    dir: checkArgs:
    let
      entries = builtins.readDir dir;
      directories = lib.filterAttrs (_: type: type == "directory") entries;
      # A fixture tree carries no Nix, so it cannot be a check by accident. Anything else that
      # holds a `.nix` file is a check the discovery did not find, and that is a defect.
      unknown = lib.filter (
        name: !(builtins.elem name reserved) && builtins.pathExists (dir + "/${name}/default.nix")
      ) (builtins.attrNames directories);
      files = lib.filterAttrs (
        name: type: type == "regular" && lib.hasSuffix ".nix" name && name != "default.nix"
      ) entries;
    in
    if unknown != [ ] then
      throw "check discovery: ${toString dir} contains ${lib.concatStringsSep ", " unknown}; a check is a file, and lib/ is the only directory"
    else
      lib.mapAttrs' (
        file: _: lib.nameValuePair (lib.removeSuffix ".nix" file) (import (dir + "/${file}") checkArgs)
      ) files;
in
{
  inherit discover;
}
