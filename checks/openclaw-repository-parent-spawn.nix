# A visible placed spawn from a repository session must give the child an
# isolated checkout of the parent's *live* working tree. The failure this
# catches: a child silently starts from the parent's previous-turn checkpoint
# (losing same-turn edits), from the Gateway's default checkout (wrong
# repository), or a capture that claims/releases the parent turn or mutates the
# parent's accepted checkpoint.
#
# The check builds the patched package and the unpatched baseline package and
# runs the real exported preparation and capture controller against a real
# repository-workspace store. The tunnel is a test double; the checkpoint
# staging, publication and child isolation are the package's own code.
{
  pkgs,
  inputs,
  ...
}:
let
  gateway = pkgs.openclaw-gateway;
  baseline = inputs.openclaw.packages.${pkgs.stdenv.hostPlatform.system}.openclaw-gateway;
in
pkgs.runCommand "openclaw-repository-parent-spawn-check"
  {
    nativeBuildInputs = [
      pkgs.git
      pkgs.nodejs
    ];
  }
  ''
    set -euo pipefail
    export HOME=$TMPDIR/home
    mkdir -p "$HOME"
    export GIT_CONFIG_NOSYSTEM=1

    OPENCLAW_PACKAGE_ROOT=${gateway}/lib/node_modules/openclaw \
    OPENCLAW_BASELINE_ROOT=${baseline}/lib/node_modules/openclaw \
      node ${../packages/overlays/fix/openclaw/test/repository-parent-spawn.test.mjs}

    touch $out
  ''
