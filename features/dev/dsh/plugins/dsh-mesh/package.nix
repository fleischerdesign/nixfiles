# features/dev/dsh/plugins/dsh-mesh/package.nix
# dsh-mesh: Distributed peer-to-peer mesh synchronization with CvRDT state-based gossip.
{
  lib,
  stdenv,
  nodejs_24,
  typescript,
  dsh,
  ...
}:

let
  manifest = builtins.fromJSON (builtins.readFile ./manifest.json);
  pname = manifest.name;
in
stdenv.mkDerivation {
  inherit pname;
  inherit (manifest) version;

  src = ./.;

  nativeBuildInputs = [
    nodejs_24
    typescript
  ];

  buildPhase = ''
    runHook preBuild
    mkdir -p node_modules/@deepseek-ai
    if [ -d "${dsh}/lib/dsh/node_modules/@deepseek-ai" ]; then
      ln -s ${dsh}/lib/dsh/node_modules/@deepseek-ai/* node_modules/@deepseek-ai/
    fi
    if [ -d "${dsh}/lib/dsh/node_modules/@types" ]; then
      ln -s ${dsh}/lib/dsh/node_modules/@types node_modules/@types
    fi

    tsc --project tsconfig.json
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/node_modules/${pname}
    cp -r lib package.json cordis.patch.yml $out/lib/node_modules/${pname}/
    runHook postInstall
  '';

  passthru.dshPluginName = manifest.bundle or pname;

  meta = {
    description = manifest.description;
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
