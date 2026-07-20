# lib/core/module-loader.nix
# Recursive module auto-discovery utility for NixOS features.
{ lib }:

let
  findModules =
    dir:
    let
      entries = builtins.readDir dir;
      current = if lib.hasAttr "default.nix" entries then [ (dir + "/default.nix") ] else [ ];
      subdirs = lib.filterAttrs (_: v: v == "directory") entries;
      subModules = lib.concatMap (name: findModules (dir + "/${name}")) (builtins.attrNames subdirs);
    in
    current ++ subModules;
in
{
  inherit findModules;
}
