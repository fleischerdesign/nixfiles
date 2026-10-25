{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
let
  manifest = lib.importJSON ./manifest.json;
in
buildGoModule {
  pname = "zennotes-tui";
  inherit (manifest) version;

  src = fetchFromGitHub {
    inherit (manifest.upstream) owner repo;
    rev = "v${manifest.version}";
    hash = manifest.srcHash;
  };

  vendorHash = manifest.vendorHash;
  subPackages = [ "cmd/zn" ];
  ldflags = [ "-s" "-w" ];

  meta = {
    description = "Keyboard-first ZenNotes CLI, TUI and MCP server";
    homepage = "https://zennotes.org/tui";
    license = lib.licenses.mit;
    mainProgram = "zn";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
