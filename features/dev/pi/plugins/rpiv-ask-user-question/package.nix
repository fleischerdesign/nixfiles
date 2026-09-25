# features/dev/pi/plugins/rpiv-ask-user-question/package.nix
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

  dontNpmBuild = true;
  npmFlags = [
    "--legacy-peer-deps"
    "--omit=dev"
  ];

  meta = with lib; {
    description = "Structured interactive questionnaire extension for Pi";
    homepage = "https://github.com/juicesharp/rpiv-mono";
    license = licenses.mit;
  };
}
