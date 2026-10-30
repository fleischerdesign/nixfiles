# Pi plugin discovery.
#
# A directory that holds a regular `plugin.nix` is one plugin, and the file name is the marker -
# the same contract `lib/discovery.nix` uses for modules. A distinctive marker keeps a helper
# directory from being imported as a plugin, and it keeps the plugin tree free of a manifest that
# could drift from the directories beside it.
#
# A plugin file returns `{ name, package }`:
#
#   * `name`    the directory name Pi sees under `~/.pi/agent/extensions/`.
#   * `package` a derivation whose root is the plugin itself - either an `index.ts` (or
#               `index.js`) at the top, or a `package.json` carrying a `pi.extensions` field.
#
# Both shapes are what Pi auto-discovers in its extension directory, so the loader only has to
# produce them; it does not know what a plugin does.
{ lib }:

let
  find =
    dir:
    let
      entries = builtins.readDir dir;
      here =
        if !(entries ? "plugin.nix") then
          [ ]
        else if entries."plugin.nix" == "regular" then
          [ (import (dir + "/plugin.nix")) ]
        else
          throw "pi plugin discovery: ${toString dir}/plugin.nix is a ${entries."plugin.nix"}, not a regular file";
      subdirs = lib.filterAttrs (_: kind: kind == "directory") entries;
    in
    here ++ lib.concatMap (name: find (dir + "/${name}")) (builtins.attrNames subdirs);

  validate =
    dir: plugin:
    if !(plugin ? name) || !(plugin ? package) then
      throw "pi plugin discovery: a plugin under ${toString dir} must return { name, package }"
    else
      plugin;
in
{
  # The plugin tree is optional: a host that enables Pi without declaring plugins gets an empty
  # list, not a build failure. Ordering is by name so the generated directory is stable.
  findPlugins =
    dir:
    let
      found = map (validate dir) (if builtins.pathExists dir then find dir else [ ]);
      names = map (plugin: plugin.name) found;
      duplicates = lib.unique (
        builtins.filter (name: builtins.length (builtins.filter (other: other == name) names) > 1) names
      );
    in
    if duplicates != [ ] then
      throw "pi plugin discovery: duplicate plugin names: ${lib.concatStringsSep ", " duplicates}"
    else
      lib.sort (a: b: a.name < b.name) found;
}
