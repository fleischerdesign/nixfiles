# features/dev/pi/plugins/pi-background-tasks/package.nix
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
    fixIntegrity = true;
  };

  dontNpmBuild = true;
  npmFlags = [
    "--legacy-peer-deps"
    "--omit=dev"
    "--ignore-scripts"
  ];

  meta = with lib; {
    description = "Pi extension for durable background shell tasks, read-only delegated agents, and fusion workflows";
    homepage = "https://github.com/ismailsaleekh/pi-background-tasks";
    license = licenses.mit;
  };
}
