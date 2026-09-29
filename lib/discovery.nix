# Recursive module discovery: a regular file named `nixos.nix` marks a NixOS module, and a
# regular `home.nix` beside it marks the account-scope half of the same directory.
#
# The marker is a name of its own on purpose. When the scanner looked for `default.nix`, the same name
# meant "NixOS module" under `features/` and "importable package or library" everywhere else, so a helper
# extracted to `lib/default.nix` silently became a module - imported, enabled, and backed by nothing. A
# distinctive marker removes the ambiguity instead of requiring an exclusion list that has to be
# remembered for every new kind of directory.
{ lib }:

let
  # A file that shares a marker's name but is not a regular file is a mistake, not something to
  # skip quietly, so every marker goes through the same check.
  findNamed =
    fileName: dir:
    let
      entries = builtins.readDir dir;
      here =
        if !(entries ? ${fileName}) then
          [ ]
        else if entries.${fileName} == "regular" then
          [ (dir + "/${fileName}") ]
        else
          throw "module discovery: ${toString dir}/${fileName} is a ${entries.${fileName}}, not a regular file";
      subdirs = lib.filterAttrs (_: value: value == "directory") entries;
      subModules = lib.concatMap (name: findNamed fileName (dir + "/${name}")) (
        builtins.attrNames subdirs
      );
    in
    here ++ subModules;
in
{
  inherit findNamed;
  findModules = findNamed "nixos.nix";
}
