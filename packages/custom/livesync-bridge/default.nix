# packages/custom/livesync-bridge/default.nix
# Custom package wrapper for vrtmrz/livesync-bridge
{
  deno,
  fetchFromGitHub,
  lib,
  makeWrapper,
  stdenv,
}:
let
  manifest = builtins.fromJSON (builtins.readFile ./manifest.json);
in
stdenv.mkDerivation {
  pname = manifest.name;
  inherit (manifest) version;

  src = fetchFromGitHub {
    inherit (manifest.upstream) owner repo;
    inherit (manifest) rev;
    hash = manifest.srcHash;
  };

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/livesync-bridge" "$out/bin"
    cp -r . "$out/lib/livesync-bridge/"

    makeWrapper "${deno}/bin/deno" "$out/bin/livesync-bridge" \
      --add-flags "run" \
      --add-flags "-A" \
      --add-flags "--node-modules-dir=auto" \
      --add-flags "$out/lib/livesync-bridge/main.ts"
    runHook postInstall
  '';

  meta = {
    description = "Bidirectional synchronizer between CouchDB LiveSync and local filesystem";
    homepage = "https://github.com/vrtmrz/livesync-bridge";
    license = lib.licenses.mit;
    mainProgram = "livesync-bridge";
  };
}
