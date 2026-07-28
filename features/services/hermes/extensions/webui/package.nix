# features/services/hermes/extensions/webui/package.nix — WebUI package
#
# Thin wrapper around the upstream hermes-webui source (nesquena/hermes-webui).
# Copies the Python runtime files (bootstrap.py, server.py, api/, static/)
# and wraps bootstrap.py with a Nix-provided Python environment.
#
# Design decisions:
#   - HERMES_WEBUI_DISABLE_LOCAL_VENV=1  Prevents bootstrap.py from
#     creating its own Python venv at runtime — we use the Nix-built
#     environment instead.
#   - --skip-agent-install                The agent is installed separately
#     by the core hermes-agent package.
#   - Entry point: bootstrap.py           Not -m hermes_webui.server.
#     The upstream bootstrap handles venv provisioning, state init,
#     foreground/daemon mode, and the HTTP server lifecycle.
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
    rev = manifest.rev;
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

    cp $src/bootstrap.py $out/hermes-webui/
    cp $src/server.py $out/hermes-webui/
    cp $src/mcp_server.py $out/hermes-webui/
    cp $src/requirements.txt $out/hermes-webui/
    cp -r $src/api $out/hermes-webui/
    cp -r $src/static $out/hermes-webui/

    makeBinaryWrapper ${pythonEnv}/bin/python3 $out/bin/hermes-webui \
      --set HERMES_WEBUI_DISABLE_LOCAL_VENV 1 \
      --add-flags "$out/hermes-webui/bootstrap.py --foreground --no-browser --skip-agent-install"

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
