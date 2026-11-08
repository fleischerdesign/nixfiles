# packages/custom/openclaw-node-workspace/default.nix
# Runtime plugin root for the node-workspace plugin: the built JavaScript, its
# manifest and its two runtime dependencies. The plugin is pinned to a revision
# rather than a branch so a fleet build is reproducible; bump the revision, the
# source hash and npmDepsHash together.
{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:
buildNpmPackage {
  pname = "openclaw-runtime-plugin-node-workspace";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "fleischerdesign";
    repo = "openclaw-node-workspace";
    rev = "7be550dcfbc90ee41f25eea690dd6a3996c3119a";
    hash = "sha256-UGowDcoYci2XBVdIICmYuq7CPtCsCqXugZ4d2UiAua8=";
  };

  npmDepsHash = "sha256-luH8/9XstxpnT7mbNiIlAB2vo/7uLL1eXH/4y/wPGuY=";
  npmFlags = [ "--ignore-scripts" ];

  # `npm run build` type-checks and emits dist/, then bundles the Control UI
  # entry with esbuild. Both are dev dependencies, so pruning happens after it.
  buildPhase = ''
    runHook preBuild
    npm run build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    npm prune --omit=dev --offline --ignore-scripts
    mkdir -p "$out"
    cp -r dist openclaw.plugin.json package.json README.md docs "$out"/
    cp -r node_modules "$out"/node_modules

    runHook postInstall
  '';

  meta = {
    description = "OpenClaw plugin that publishes a workspace to a paired node and returns selected changes";
    license = lib.licenses.unfree; # No licence chosen yet; the package is not redistributable.
  };
}
