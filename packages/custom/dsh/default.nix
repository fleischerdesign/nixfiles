# packages/custom/dsh/default.nix
# DeepSeek Harness (dsh) — built from the upstream pnpm workspace monorepo.
# The workspace layout is the runtime layout: the CLI mounts configTrees with
# paths relative to the repository root and the profile launcher resolves
# bundles from the installation workspace, so the full built tree is deployed.
{
  lib,
  stdenv,
  nodejs_24,
  pnpm_11,
  fetchFromGitHub,
  fetchPnpmDeps,
  pnpmConfigHook,
  makeWrapper,
  python3,
}:

let
  manifest = builtins.fromJSON (builtins.readFile ./manifest.json);
  pname = manifest.name;
  inherit (manifest) version;
  tagPrefix = manifest.upstream.tagPrefix or "v";
  src = fetchFromGitHub {
    owner = manifest.upstream.owner;
    repo = manifest.upstream.repo;
    rev = "${tagPrefix}${version}";
    hash = manifest.srcHash;
  };
  # fetcherVersion 4 is required for pnpm >= 11 (see nixpkgs fetch-pnpm-deps).
  pnpmDeps = fetchPnpmDeps {
    inherit pname version src;
    pnpm = pnpm_11;
    hash = manifest.npmDepsHash;
    fetcherVersion = 4;
  };
in
stdenv.mkDerivation {
  inherit
    pname
    version
    src
    pnpmDeps
    ;

  nativeBuildInputs = [
    nodejs_24
    pnpm_11
    pnpmConfigHook
    makeWrapper
    # node-gyp builds for native dependency addons (fs-ext, node-pty).
    python3
  ];

  env = {
    HOME = "/tmp";
    # node-gyp builds against the local Node headers (offline sandbox).
    npm_config_nodedir = "${nodejs_24}";
  };

  # pnpmConfigHook installs with --ignore-scripts, so the three node-gyp
  # builds upstream allows (fs-ext, koffi, node-pty) never run during
  # install. Rebuild them against the installed tree; the artifacts land in
  # the node_modules copy that installPhase deploys.
  preBuild = ''
    pnpm -r rebuild fs-ext koffi node-pty
  '';

  # The official build embeds the source commit in browser metadata via `git
  # rev-parse`; no git binary/metadata exists in the sandbox, so the pinned
  # tag commit is injected explicitly (dsh-v0.1.3-alpha.1).
  env.DSH_CLIENT_COMMIT_HASH = "d347e70";

  # Compiles the full host TypeScript project (including the apps/cli entry)
  # and the web frontend. Upstream runs build:lib with a 4 GiB heap guard.
  buildPhase = ''
    runHook preBuild
    NODE_OPTIONS="--max-old-space-size=8192" pnpm run build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib $out/bin
    cp -r . $out/lib/dsh
    # The CLI entry lives at apps/cli (bin: lib/bin.js); its bare workspace
    # imports resolve through apps/cli/node_modules, mirroring `pnpm dsh`.
    # --expose-internals is the loader's primary builtin-module route (the
    # prebuilt require-builtin addon is not ABI-stable across Node versions).
    makeWrapper ${nodejs_24}/bin/node $out/bin/dsh \
      --add-flags "--expose-internals" \
      --add-flags "$out/lib/dsh/apps/cli/lib/bin.js"
    # Mirror the published flat npm layout: link every workspace package into
    # the tree root's node_modules so the Cordis loader's bare-name imports
    # resolve from vendor/loader.
    node ${./link-workspace-packages.mjs} $out/lib/dsh
    runHook postInstall
  '';

  # The vitest suites require network fixtures; correctness is covered by
  # evaluation (nix flake check) and the post-build smoke test.
  doCheck = false;

  passthru = { inherit pnpmDeps; };

  meta = {
    description = "DeepSeek Harness: open-source agent harness by DeepSeek AI (everything is a plugin)";
    homepage = "https://github.com/deepseek-ai/deepseek-harness";
    license = lib.licenses.mit;
    mainProgram = "dsh";
    platforms = lib.platforms.linux;
  };
}
