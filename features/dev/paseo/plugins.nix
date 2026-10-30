# Paseo plugin declarations.
#
# A directory that holds a regular `plugin.nix` is one plugin, and the file name is the marker -
# the same contract `lib/discovery.nix` uses for modules and `features/dev/pi/plugins.nix` uses for
# extensions.
#
# A plugin file returns `{ name, source }`:
#
#   * `name`   a stable local label, used for messages and for the daemon's saved entry.
#   * `source` a Paseo package source: `npm:<package>@<version>` or `git:<host>/<repo>@<ref>`.
#
# Unlike Pi, the daemon does not scan a directory: `$PASEO_HOME/plugins/sources.json` records only
# Git and npm sources, and the daemon checks them out and builds them itself. A plate of files in
# the store therefore cannot be a Paseo plugin - the source has to be declared, and the daemon has
# to fetch it. The loader enforces a pinned version or ref, because an unpinned source would make
# the declaration decorative.
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
          throw "paseo plugin discovery: ${toString dir}/plugin.nix is a ${entries."plugin.nix"}, not a regular file";
      subdirs = lib.filterAttrs (_: kind: kind == "directory") entries;
    in
    here ++ lib.concatMap (name: find (dir + "/${name}")) (builtins.attrNames subdirs);

  # `npm:a@1.2.3` and `git:host/owner/repo@<ref>` are both pinned by their trailing `@`. A source
  # without one would drift on every daemon restart, which is exactly what declaring it in Nix is
  # supposed to prevent.
  validate =
    dir: plugin:
    let
      prefix = builtins.substring 0 4 (plugin.source or "");
    in
    if !(plugin ? name) || !(plugin ? source) then
      throw "paseo plugin discovery: a plugin under ${toString dir} must return { name, source }"
    else if prefix != "npm:" && prefix != "git:" then
      throw "paseo plugin discovery: ${plugin.name} must name an npm: or git: source"
    else if builtins.length (lib.splitString "@" plugin.source) < 2 then
      throw "paseo plugin discovery: ${plugin.name} pins no version or ref"
    else
      plugin;
in
{
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
      throw "paseo plugin discovery: duplicate plugin names: ${lib.concatStringsSep ", " duplicates}"
    else
      lib.sort (a: b: a.name < b.name) found;
}
