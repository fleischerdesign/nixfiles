{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  xdg-utils,
  libsecret,
}:
let
  manifest = builtins.fromJSON (builtins.readFile ./manifest.json);
in
stdenv.mkDerivation {
  pname = manifest.name;
  inherit (manifest) version;
  src = fetchurl {
    url = "https://github.com/${manifest.upstream.owner}/${manifest.upstream.repo}/releases/download/v${manifest.version}/${manifest.upstream.assetName}";
    inherit (manifest) hash;
  };
  sourceRoot = ".";
  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];
  buildInputs = [ stdenv.cc.cc.lib ];
  runtimeDependencies = [ libsecret ];
  dontBuild = true;
  dontStrip = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/opencodex" "$out/bin"
    cp -a ocx gui keyring "$out/lib/opencodex/"
    makeWrapper "$out/lib/opencodex/ocx" "$out/bin/ocx" \
      --suffix PATH : ${lib.makeBinPath [ xdg-utils ]}
    ln -s ocx "$out/bin/opencodex"
    runHook postInstall
  '';
  meta = {
    description = "Local provider proxy and model catalog for Codex";
    homepage = "https://github.com/lidge-jun/opencodex";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "ocx";
  };
}
