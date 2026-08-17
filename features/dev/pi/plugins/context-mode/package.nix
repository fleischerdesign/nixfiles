# features/dev/pi/plugins/context-mode/package.nix
# context-mode ships no package-lock.json upstream, so we vendor a generated one
# (./package-lock.json). better-sqlite3's native addon is intentionally skipped
# via `--ignore-scripts` (buildNpmPackage default); at runtime context-mode uses
# the built-in node:sqlite on Node >= 22.5 instead.
{
  buildNpmPackage,
  lib,
  mkSrc,
  pnameOf,
}:
let
  manifest = builtins.fromJSON (builtins.readFile ./manifest.json);
in
buildNpmPackage {
  pname = pnameOf manifest.name;
  inherit (manifest) version npmDepsHash;

  src = mkSrc {
    inherit manifest;
    lockfile = ./package-lock.json;
  };

  # context-mode's `pi` manifest points to ./build/adapters/pi/extension.js,
  # which is produced by `npm run build` (tsc + esbuild bundle). Run it.
  npmFlags = [ "--legacy-peer-deps" ];

  meta = with lib; {
    description = "Context management and compression for coding agents";
    homepage = "https://github.com/mksglu/context-mode";
    license = licenses.elastic20;
  };
}
