# features/dev/pi/lib/plugins.nix
# Shared plugin discovery + source helper for the pi feature.
# - Discovers ./plugins/<name>/package.nix (package derivations)
# - Discovers ./plugins/<name>/module.nix (NixOS/Home-Manager modules)
# - Derives each plugin's pi package directory from its manifest `name` (= pname).
# - mkSrc wraps fetchFromGitHub / fetchurl with optional integrity-fix / lockfile injection.
{
  lib,
  pkgs ? null,
}:
let
  pluginsDir = ../plugins;
  entries = builtins.readDir pluginsDir;
  pluginDirNames = builtins.attrNames entries;

  readManifest = name: builtins.fromJSON (builtins.readFile (pluginsDir + "/${name}/manifest.json"));

  # Store name for buildNpmPackage (strips an npm scope, e.g. "@scope/pkg" -> "pkg").
  pnameOf = name: lib.last (lib.splitString "/" name);

  pluginNames = lib.filter (
    name: entries.${name} == "directory" && builtins.pathExists (pluginsDir + "/${name}/package.nix")
  ) pluginDirNames;

  modules = lib.concatMap (
    name:
    lib.optional (
      entries.${name} == "directory" && builtins.pathExists (pluginsDir + "/${name}/module.nix")
    ) (pluginsDir + "/${name}/module.nix")
  ) pluginDirNames;

  mkSrc =
    {
      manifest,
      fixIntegrity ? false,
      lockfile ? null,
      tarballUrl ? null,
    }:
    let
      src =
        if tarballUrl != null then
          pkgs.fetchurl {
            url = tarballUrl;
            hash = manifest.srcHash;
          }
        else
          pkgs.fetchFromGitHub {
            owner = manifest.upstream.owner;
            repo = manifest.upstream.repo;
            rev = manifest.rev;
            hash = manifest.srcHash;
          };
    in
    if !fixIntegrity && lockfile == null then
      src
    else
      pkgs.stdenv.mkDerivation (
        {
          name = "${manifest.name}-src";
          inherit src;
          nativeBuildInputs = [ pkgs.nodejs ];
          buildPhase = lib.concatStringsSep "\n" (
            lib.optional fixIntegrity "node ${./fix-pi-integrity.mjs} package-lock.json"
            ++ lib.optional (lockfile != null) "cp ${lockfile} package-lock.json"
          );
          installPhase = "cp -r . \"$out\"";
        }
        // lib.optionalAttrs (tarballUrl != null) { sourceRoot = "package"; }
      );

  derivations =
    if pkgs == null then
      { }
    else
      lib.genAttrs pluginNames (
        name: pkgs.callPackage (pluginsDir + "/${name}/package.nix") { inherit mkSrc pnameOf; }
      );

  packageDirs =
    if pkgs == null then
      { }
    else
      lib.mapAttrs (name: drv: "${drv}/lib/node_modules/${(readManifest name).name}") derivations;
in
{
  inherit
    pluginNames
    derivations
    packageDirs
    modules
    ;
}
