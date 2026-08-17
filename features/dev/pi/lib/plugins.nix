# features/dev/pi/lib/plugins.nix
# Shared plugin discovery + source helper for the pi feature.
# - Discovers ./plugins/<name>/package.nix (not default.nix — avoids the module loader).
# - Derives each plugin's pi package directory from its manifest `name` (= pname).
# - mkSrc wraps fetchFromGitHub with optional integrity-fix / lockfile injection.
{
  lib,
  pkgs,
}:
let
  pluginsDir = ../plugins;

  readManifest = name: builtins.fromJSON (builtins.readFile (pluginsDir + "/${name}/manifest.json"));

  # Store name for buildNpmPackage (strips an npm scope, e.g. "@scope/pkg" -> "pkg").
  pnameOf = name: lib.last (lib.splitString "/" name);

  pluginNames =
    let
      entries = builtins.readDir pluginsDir;
    in
    lib.filter (
      name: entries.${name} == "directory" && builtins.pathExists (pluginsDir + "/${name}/package.nix")
    ) (builtins.attrNames entries);

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

  derivations = lib.genAttrs pluginNames (
    name: pkgs.callPackage (pluginsDir + "/${name}/package.nix") { inherit mkSrc pnameOf; }
  );
in
{
  inherit pluginNames derivations;
  # Pi loads each plugin from buildNpmPackage's output: $out/lib/node_modules/<pname>.
  packageDirs = lib.mapAttrs (
    name: drv: "${drv}/lib/node_modules/${(readManifest name).name}"
  ) derivations;
}
