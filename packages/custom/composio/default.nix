{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  unzip,
}:
let
  manifest = builtins.fromJSON (builtins.readFile ./manifest.json);
  # The CLI is released from a monorepo with scoped tags, e.g. @composio/cli@0.4.5.
  tag = "@composio/cli@${manifest.version}";
  encodedTag = builtins.replaceStrings [ "@" ] [ "%40" ] tag;
in
stdenv.mkDerivation {
  pname = "composio";
  inherit (manifest) version;

  src = fetchurl {
    url = "https://github.com/${manifest.upstream.owner}/${manifest.upstream.repo}/releases/download/${encodedTag}/${manifest.upstream.assetName}";
    inherit (manifest) hash;
  };

  sourceRoot = "composio-linux-x64";

  nativeBuildInputs = [
    autoPatchelfHook
    unzip
  ];
  buildInputs = [ stdenv.cc.cc.lib ];

  dontBuild = true;
  # The single-file runtime is load-bearing; stripping can break it.
  dontStrip = true;

  # Helper modules are resolved next to the executable, so the whole release
  # tree is installed together and only the entry point is linked into bin/.
  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib $out/bin
    cp -a . $out/lib/composio
    ln -s $out/lib/composio/composio $out/bin/composio
    runHook postInstall
  '';

  meta = {
    description = "Composio CLI for authenticated app actions from agents";
    homepage = "https://docs.composio.dev/docs/cli";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "composio";
  };
}
