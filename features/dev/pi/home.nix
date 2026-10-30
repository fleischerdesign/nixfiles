{
  lib,
  ...
}:

let
  # The plugin tree is discovered, never listed: `plugins.nix` beside this file owns the contract,
  # and `plugins/<name>/plugin.nix` is one plugin.
  plugins = (import ./plugins.nix { inherit lib; }).findPlugins ./plugins;
in
{
  # Pi auto-discovers one extension per directory under its agent directory, so a store symlink per
  # plugin is the whole integration.
  #
  # Settings are deliberately not written here: `pi install` and `/login` maintain
  # `settings.json` at runtime, and a Nix-owned copy would either be replaced or fight the CLI.
  home.file = lib.listToAttrs (
    map (plugin: {
      name = ".pi/agent/extensions/${plugin.name}";
      value.source = plugin.package;
    }) plugins
  );
}
