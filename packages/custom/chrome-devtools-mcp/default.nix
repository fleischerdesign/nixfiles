# packages/custom/chrome-devtools-mcp/default.nix
# Hermetic packaging of the Chrome DevTools MCP server. The npm tarball ships a
# pre-built `build/` tree with zero runtime dependencies, so a plain unpack +
# node wrapper suffices.
{
  fetchurl,
  lib,
  makeWrapper,
  nodejs,
  stdenv,
}:
let
  manifest = builtins.fromJSON (builtins.readFile ./manifest.json);
in
stdenv.mkDerivation {
  pname = "chrome-devtools-mcp";
  inherit (manifest) version;

  src = fetchurl {
    url = "https://registry.npmjs.org/chrome-devtools-mcp/-/chrome-devtools-mcp-${manifest.version}.tgz";
    hash = manifest.srcHash;
  };

  sourceRoot = "package";

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib" "$out/bin"
    cp -r . "$out/lib/chrome-devtools-mcp"
    makeWrapper "${nodejs}/bin/node" "$out/bin/chrome-devtools-mcp" \
      --add-flags "$out/lib/chrome-devtools-mcp/build/src/bin/chrome-devtools-mcp.js"
    runHook postInstall
  '';

  meta = with lib; {
    description = "MCP server for Chrome DevTools automation";
    homepage = "https://github.com/ChromeDevTools/chrome-devtools-mcp";
    license = licenses.asl20;
    mainProgram = "chrome-devtools-mcp";
  };
}
