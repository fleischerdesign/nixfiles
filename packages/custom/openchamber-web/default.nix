{
  buildNpmPackage,
  lib,
  makeWrapper,
  nodejs_24,
}:
buildNpmPackage {
  pname = "openchamber-web";
  version = "2.3.3";
  src = ./.;
  npmDepsHash = "sha256-LXn4P3MX4JR2SimtQ2U5jhPgHKyTMXNav7oioEgJyFY=";
  dontNpmBuild = true;
  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/openchamber" "$out/bin"
    cp -r node_modules "$out/lib/openchamber/"
    makeWrapper "${nodejs_24}/bin/node" "$out/bin/openchamber" \
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
