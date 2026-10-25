{
  lib,
  buildGoModule,
  fetchFromGitHub,
  fetchurl,
}:
let
  manifest = lib.importJSON ./manifest.json;
  webArchive = fetchurl {
    inherit (manifest.webArtifact) url;
    hash = manifest.webArtifact.hash;
  };
in
buildGoModule {
  pname = "zennotes-server";
  inherit (manifest) version;

  src = fetchFromGitHub {
    inherit (manifest.upstream) owner repo;
    rev = "v${manifest.version}";
    hash = manifest.srcHash;
  };

  vendorHash = manifest.vendorHash;
  subPackages = [ "cmd/zennotes-server" ];
  tags = [ "embed_web" ];
  ldflags = [ "-s" "-w" ];

  postConfigure = ''
    go run ./cmd/prepare-web \
      -manifest ${./web-manifest.json} \
      -archive ${webArchive} \
      -output web/dist
    go test -tags=embed_web ./web
  '';

  meta = {
    description = "Server for hosting remote ZenNotes vaults";
    homepage = "https://zennotes.org/";
    license = lib.licenses.mit;
    mainProgram = "zennotes-server";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
