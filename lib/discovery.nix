# Recursive NixOS module discovery: a regular file named `nixos.nix` marks a module.
#
# The marker is a name of its own on purpose. When the scanner looked for `default.nix`, the same name
# meant "NixOS module" under `features/` and "importable package or library" everywhere else, so a helper
# extracted to `lib/default.nix` silently became a module - imported, enabled, and backed by nothing. A
# distinctive marker removes the ambiguity instead of requiring an exclusion list that has to be
# remembered for every new kind of directory.
{ lib }:

let
  marker = "nixos.nix";

  findModules =
    dir:
    let
      entries = builtins.readDir dir;
      here =
        if !(entries ? ${marker}) then
          [ ]
        else if entries.${marker} == "regular" then
          [ (dir + "/${marker}") ]
        else
          # A directory or a symlink named like the marker is a mistake, not a module to skip quietly.
          throw "module discovery: ${toString dir}/${marker} is a ${entries.${marker}}, not a regular file";
      subdirs = lib.filterAttrs (_: value: value == "directory") entries;
      subModules = lib.concatMap (name: findModules (dir + "/${name}")) (builtins.attrNames subdirs);
    in
    here ++ subModules;
in
{
  inherit findModules;
}
