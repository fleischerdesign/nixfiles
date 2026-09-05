# features/dev/dsh/lib/plugins.nix — Plugin discovery and generated options.
#
# Mirrors the pi feature's plugin system (features/dev/pi/lib/plugins.nix),
# adapted to dsh's bundle model:
#   - Discovers ./plugins/<name>/package.nix (package derivations). Each
#     derivation reads its own manifest.json (same convention as
#     packages/custom: version, srcHash, npmDepsHash, upstream) and exposes
#     passthru.dshPluginName. The custom-package updater covers
#     features/**/manifest.json, so plugin manifests update automatically.
#   - Provides a name-agnostic options module exposing
#     my.features.dev.dsh.plugins.<name>.enable (default true).
#   - Activation: the dsh package is overridden with extraPlugins; bundle
#     rows are emitted into the home Cordis patch layer by the feature.
{
  lib,
  pkgs,
}:
let
  pluginsDir = ../plugins;
  entries = builtins.readDir pluginsDir;

  pluginNames = lib.filter (
    name: entries.${name} == "directory" && builtins.pathExists (pluginsDir + "/${name}/package.nix")
  ) (lib.attrNames entries);

  derivations = lib.genAttrs pluginNames (
    name: pkgs.callPackage (pluginsDir + "/${name}/package.nix") { }
  );

  # The npm package name each bundle row must reference. Plugins declare it
  # as `bundle` in their manifest.json (their own cordis.patch.yml row id
  # alongside, if the upstream patch uses a different entry id).
  bundleNameOf =
    name:
    let
      manifest = builtins.fromJSON (builtins.readFile (pluginsDir + "/${name}/manifest.json"));
    in
    manifest.bundle or manifest.name;

  # One generated module exposing the enable switches for every discovered
  # plugin (name-agnostic: adding a plugin directory needs no edit here).
  optionsModule =
    { lib, ... }:
    {
      options.my.features.dev.dsh.plugins = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options.enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Whether this dsh plugin is built, injected, and activated.";
            };
          }
        );
        default = { };
        description = "Per-plugin switches for the auto-discovered dsh plugins.";
      };
    };
in
{
  inherit
    pluginNames
    derivations
    bundleNameOf
    optionsModule
    ;
}
