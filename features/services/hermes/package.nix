# features/services/hermes/package.nix — Hermes Agent application package
#
# Two-phase derivation pattern:
#   1. hermesBuild (buildPythonPackage)  Compiles the Python wheel from
#      the upstream source. Dependencies go into propagatedBuildInputs
#      so the entry-point wrappers can find them at import time.
#   2. Outer stdenv.mkDerivation          Assembles the final package:
#      symlinks immutable assets (skills, locales, plugins) from the
#      source tree, symlinks the pre-built web_dist (npm → Vite output
#      at hermes_cli/web_dist/), and wraps the three entry-point
#      binaries (hermes, hermes-agent, hermes-acp) with HERMES_*
#      environment variables the agent reads at startup via wrapProgram.
#
# Design decisions:
#   - HERMES_NIX_BUILD=1          Bypasses upstream's setup.py guard that
#                                 blocks non-Nix pip/sdist installs.
#   - ELECTRON_SKIP_BINARY_DOWNLOAD=1
#                                 The npm monorepo includes electron for
#                                 the desktop/TUI workspaces. We only
#                                 need the web workspace; this prevents
#                                 electron's postinstall from fetching
#                                 its binary in the Nix sandbox.
#   - pythonEnv (withPackages)    Exposed via passthru so the webui
#                                 extension can reference a Python
#                                 interpreter that has hermes-agent
#                                 available (HERMES_WEBUI_PYTHON).
#   - extraPythonPackages         Injection point for extension packages
#                                 (mnemosyne, ddgs). These become part of
#                                 the agent's Python environment without
#                                 rebuilding the core wheel.
#   - setuptools version patch    Upstream constrains setuptools <83 but
#                                 nixpkgs ships 83.x. We relax the
#                                 constraint in pyproject.toml via
#                                 prePatch substituteInPlace.
{
  lib,
  stdenv,
  fetchFromGitHub,
  nodejs_22,
  buildNpmPackage,
  python3Packages,
  git,
  ripgrep,
  openssh,
  ffmpeg,
  extraPythonPackages ? [ ],
}:

let
  manifest = builtins.fromJSON (builtins.readFile ./manifest.json);

  src = fetchFromGitHub {
    owner = manifest.upstream.owner;
    repo = manifest.upstream.repo;
    rev = manifest.rev;
    hash = manifest.srcHash;
  };

  webDist = buildNpmPackage {
    pname = "hermes-gateway-web";
    version = manifest.version;
    src = src;
    npmDepsHash = manifest.npmDepsHash;
    npmWorkspace = "web";
    ELECTRON_SKIP_BINARY_DOWNLOAD = "1";
    installPhase = ''
      mkdir -p $out
      cp -r hermes_cli/web_dist/* $out/
    '';
  };

  runtimeDeps = [
    git
    ripgrep
    openssh
    ffmpeg
  ];

  hermesBuild = python3Packages.buildPythonPackage {
    pname = manifest.name;
    version = manifest.version;
    inherit src;

    pyproject = true;
    build-system = [ python3Packages.setuptools ];
    propagatedBuildInputs =
      with python3Packages;
      [
        openai
        certifi
        python-dotenv
        fire
        httpx
        rich
        tenacity
        pyyaml
        ruamel-yaml
        requests
        jinja2
        pydantic
        prompt-toolkit
        croniter
        packaging
        cryptography
      ]
      ++ extraPythonPackages;
    HERMES_NIX_BUILD = "1";
    doCheck = false;
    dontCheckRuntimeDeps = true;
    pythonImportsCheck = [ "hermes_cli" ];

    # Python 3.14 removed ThreadPoolExecutor._initializer / ._initargs entirely
    # and replaced them with ._create_worker_context().  The daemon_pool module
    # mirrors CPython 3.8–3.13 internally — the patch adapts _adjust_thread_count
    # to build the correct 3-arg _worker(executor_reference, ctx, work_queue) call.
    # Without it every concurrent tool execution fails with:
    #   AttributeError: 'DaemonThreadPoolExecutor' object has no attribute 'initializer'
    patches = [ ./fix-python314-daemon-pool.patch ];

    prePatch = ''
      substituteInPlace pyproject.toml \
        --replace-fail 'setuptools>=77.0,<83' 'setuptools>=77.0'
    '';
  };

  pythonEnv = python3Packages.python.withPackages (_: [ hermesBuild ]);

in
stdenv.mkDerivation {
  pname = manifest.name;
  version = manifest.version;
  inherit src;
  dontUnpack = true;
  dontBuild = true;
  nativeBuildInputs = [ ];

  installPhase = ''
        runHook preInstall

        mkdir -p $out/share/hermes-agent $out/bin

        ln -s ${src}/skills $out/share/hermes-agent/skills
        ln -s ${src}/optional-skills $out/share/hermes-agent/optional-skills
        ln -s ${src}/plugins $out/share/hermes-agent/plugins
        ln -s ${src}/locales $out/share/hermes-agent/locales
        ln -s ${src}/optional-mcps $out/share/hermes-agent/optional-mcps
        ln -s ${webDist} $out/share/hermes-agent/web_dist

        cat > $out/bin/hermes << HERMESWRAPPER
    #!/bin/sh
    export PATH="${lib.makeBinPath runtimeDeps}:\$PATH"
    export HERMES_BUNDLED_SKILLS='$out/share/hermes-agent/skills'
    export HERMES_OPTIONAL_SKILLS='$out/share/hermes-agent/optional-skills'
    export HERMES_BUNDLED_PLUGINS='$out/share/hermes-agent/plugins'
    export HERMES_BUNDLED_LOCALES='$out/share/hermes-agent/locales'
    export HERMES_OPTIONAL_MCPS='$out/share/hermes-agent/optional-mcps'
    export HERMES_WEB_DIST='$out/share/hermes-agent/web_dist'
    export HERMES_PYTHON='${pythonEnv}/bin/python3'
    export HERMES_NODE='${lib.getExe nodejs_22}'
    export HERMES_REVISION='${manifest.rev}'
    exec ${pythonEnv}/bin/python3 -m hermes_cli.main "\$@"
    HERMESWRAPPER
        chmod +x $out/bin/hermes

        cat > $out/bin/hermes-agent << HERMESWRAPPER
    #!/bin/sh
    export PATH="${lib.makeBinPath runtimeDeps}:\$PATH"
    export HERMES_BUNDLED_SKILLS='$out/share/hermes-agent/skills'
    export HERMES_OPTIONAL_SKILLS='$out/share/hermes-agent/optional-skills'
    export HERMES_BUNDLED_PLUGINS='$out/share/hermes-agent/plugins'
    export HERMES_BUNDLED_LOCALES='$out/share/hermes-agent/locales'
    export HERMES_OPTIONAL_MCPS='$out/share/hermes-agent/optional-mcps'
    export HERMES_WEB_DIST='$out/share/hermes-agent/web_dist'
    export HERMES_PYTHON='${pythonEnv}/bin/python3'
    export HERMES_NODE='${lib.getExe nodejs_22}'
    export HERMES_REVISION='${manifest.rev}'
    exec ${pythonEnv}/bin/python3 -m run_agent "\$@"
    HERMESWRAPPER
        chmod +x $out/bin/hermes-agent

        cat > $out/bin/hermes-acp << HERMESWRAPPER
    #!/bin/sh
    export PATH="${lib.makeBinPath runtimeDeps}:\$PATH"
    export HERMES_BUNDLED_SKILLS='$out/share/hermes-agent/skills'
    export HERMES_OPTIONAL_SKILLS='$out/share/hermes-agent/optional-skills'
    export HERMES_BUNDLED_PLUGINS='$out/share/hermes-agent/plugins'
    export HERMES_BUNDLED_LOCALES='$out/share/hermes-agent/locales'
    export HERMES_OPTIONAL_MCPS='$out/share/hermes-agent/optional-mcps'
    export HERMES_WEB_DIST='$out/share/hermes-agent/web_dist'
    export HERMES_PYTHON='${pythonEnv}/bin/python3'
    export HERMES_NODE='${lib.getExe nodejs_22}'
    export HERMES_REVISION='${manifest.rev}'
    exec ${pythonEnv}/bin/python3 -m acp_adapter.entry "\$@"
    HERMESWRAPPER
        chmod +x $out/bin/hermes-acp

        runHook postInstall
  '';

  passthru = {
    inherit pythonEnv;
    inherit (hermesBuild) overridePythonAttrs;
  };

  meta = with lib; {
    description = "The self-improving AI agent — creates skills from experience";
    homepage = "https://github.com/NousResearch/hermes-agent";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "hermes";
  };
}
