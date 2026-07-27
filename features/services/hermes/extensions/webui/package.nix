{
  stdenv,
  lib,
  fetchFromGitHub,
  makeBinaryWrapper,
  python3,
}:

let
  manifest = builtins.fromJSON (builtins.readFile ./manifest.json);

  src = fetchFromGitHub {
    owner = manifest.upstream.owner;
    repo = manifest.upstream.repo;
    rev = manifest.version;
    hash = manifest.srcHash;
  };

  pythonEnv = python3.withPackages (
    ps: with ps; [
      pyyaml
      cryptography
    ]
  );

in
stdenv.mkDerivation {
  pname = manifest.name;
  version = manifest.version;
  inherit src;
  dontBuild = true;
  nativeBuildInputs = [ makeBinaryWrapper ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/hermes-webui $out/bin

    for d in api static; do
      if [ -d $src/$d ]; then
        cp -r $src/$d $out/hermes-webui/
      fi
    done

    makeBinaryWrapper ${pythonEnv}/bin/python3 $out/bin/hermes-webui \
      --add-flags "-m hermes_webui.server" \
      --prefix PYTHONPATH : $out/hermes-webui

    runHook postInstall
  '';

  meta = with lib; {
    description = "Hermes WebUI server and static runtime";
    homepage = "https://github.com/nesquena/hermes-webui";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "hermes-webui";
  };
}
