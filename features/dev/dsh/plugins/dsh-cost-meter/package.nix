# features/dev/dsh/plugins/dsh-cost-meter/package.nix
# dsh-cost-meter: session/daily API cost tracking, budgets, price catalog,
# and peak/off-peak pricing for the dsh web UI. Ships prebuilt lib/ upstream;
# no build step. Its own node_modules carry its third-party deps (zod) while
# @deepseek-ai/* helper imports resolve through the bundle's pinned copies —
# the same layout the imperative `dsh plugin add` flow produces.
{
  lib,
  stdenv,
  nodejs_24,
  pnpm_11,
  python3,
  fetchFromGitHub,
  fetchPnpmDeps,
  pnpmConfigHook,
  ...
}:

let
  manifest = builtins.fromJSON (builtins.readFile ./manifest.json);
  pname = manifest.name;
  inherit (manifest) version;
  src = fetchFromGitHub {
    owner = manifest.upstream.owner;
    repo = manifest.upstream.repo;
    rev = manifest.upstream.rev;
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
    python3
  ];

  env.HOME = "/tmp";

  # lib/ is committed upstream; node_modules (installed by pnpmConfigHook,
  # self-contained via copy import) ships the plugin's own third-party deps.
  # @deepseek-ai/* helper copies ride along — the same layout the imperative
  # `dsh plugin add` flow produces.
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/node_modules/${pname}
    cp -r lib node_modules $out/lib/node_modules/${pname}/
    for f in package.json cordis.patch.yml README.md; do
      [ -f "$f" ] && cp "$f" $out/lib/node_modules/${pname}/
    done
    runHook postInstall
  '';

  # Bundle activation: bare-name resolution from the installation's
  # node_modules (injected by the dsh derivation's extraPlugins).
  passthru.dshPluginName = manifest.bundle or pname;

  meta = {
    description = "Session/daily API cost tracking, budgets, and price catalog for DeepSeek Harness";
    homepage = "https://github.com/Han-1413141/dsh-cost-meter";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
