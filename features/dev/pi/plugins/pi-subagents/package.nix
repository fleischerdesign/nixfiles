# features/dev/pi/plugins/pi-subagents/package.nix
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

  src = mkSrc { inherit manifest; };

  # No build step — pi loads the TypeScript entry directly via its source-loader.
  dontNpmBuild = true;
  npmFlags = [
    "--legacy-peer-deps"
    "--omit=dev"
  ];

  meta = with lib; {
    description = "Pi extension for single-agent delegation and scripted multi-agent workflows";
    homepage = "https://github.com/nicobailon/pi-subagents";
    license = licenses.mit;
  };
}
