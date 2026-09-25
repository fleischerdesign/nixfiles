{
  buildNpmPackage,
  lib,
  makeWrapper,
  nodejs_22,
}:
buildNpmPackage {
  pname = "openchamber-web";
  version = "2.0.1";
  src = ./.;
  npmDepsHash = "sha256-h60yBZCH1BIqytikCUPhPbB+VA9reonp1siEglgSkMM=";
  dontNpmBuild = true;
  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/openchamber" "$out/bin"
    cp -r node_modules "$out/lib/openchamber/"
    makeWrapper "${nodejs_22}/bin/node" "$out/bin/openchamber" \
      --add-flags "$out/lib/openchamber/node_modules/@openchamber/web/bin/cli.js"
    runHook postInstall
  '';

  meta = {
    description = "OpenChamber web and CLI workspace for OpenCode";
    homepage = "https://openchamber.dev";
    license = lib.licenses.mit;
    mainProgram = "openchamber";
  };
}
