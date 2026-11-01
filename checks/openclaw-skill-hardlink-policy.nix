# A worker turn that bundles skills dies with `hardlink: hardlinked path not allowed`
# when the optimised store hardlinked a bundled, custodian or plugin skill file. The
# local dist patch must relax exactly that read for immutable store outputs and leave
# mutable roots rejected. This builds the real package and calls its exported reader;
# a patch that never runs, or one that turns into a blanket prefix allow, fails here.
{ pkgs, ... }:
let
  gateway = pkgs.openclaw-gateway;
in
pkgs.runCommand "openclaw-skill-hardlink-policy-check"
  {
    nativeBuildInputs = [ pkgs.nodejs ];
  }
  ''
    set -euo pipefail
    export HOME=$TMPDIR
    node ${./openclaw-skill-hardlink-policy.mjs} ${gateway}
    touch $out
  ''
