# features/dev/pi/plugins/rpiv-todo/package.nix
# @juicesharp/rpiv-todo is published standalone on npm (its monorepo sibling dep
# @juicesharp/rpiv-config resolves from the registry, not a workspace link), so we
# source it from the npm tarball and vendor a generated lockfile (upstream ships none).
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
    tarballUrl = "https://registry.npmjs.org/${manifest.name}/-/${pnameOf manifest.name}-${manifest.version}.tgz";
    lockfile = ./package-lock.json;
  };

  # No build step — pi loads the TypeScript entry directly via its source-loader.
  dontNpmBuild = true;
  npmFlags = [
    "--legacy-peer-deps"
    "--omit=dev"
  ];

  meta = with lib; {
    description = "Todo management extension for pi";
    homepage = "https://github.com/juicesharp/rpiv-mono";
    license = licenses.mit;
  };
}
