# features/dev/pi/plugins/pi-mcp-adapter/package.nix
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

  # No build step — pi loads the TypeScript entry directly via its source-loader.
  dontNpmBuild = true;
  npmFlags = [
    "--legacy-peer-deps"
    "--omit=dev"
  ];

  meta = with lib; {
    description = "MCP (Model Context Protocol) adapter extension for pi";
    homepage = "https://github.com/nicobailon/pi-mcp-adapter";
    license = licenses.mit;
  };
}
