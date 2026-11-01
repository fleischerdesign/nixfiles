# A subagent spawn from a repository-session worker fell back to the agent
# workspace and failed in `git ls-remote origin`; on a workspace with a remote it
# would have built a worktree of the wrong repository. This builds the real
# package and proves the installed decision refuses that parent before any
# workspace is resolved, while project and worktree parents keep their path.
{ pkgs, ... }:
let
  gateway = pkgs.openclaw-gateway;
in
pkgs.runCommand "openclaw-node-spawn-source-check"
  {
    nativeBuildInputs = [ pkgs.nodejs ];
  }
  ''
    set -euo pipefail
    export HOME=$TMPDIR
    node ${./openclaw-node-spawn-source.mjs} ${gateway}
    touch $out
  ''
