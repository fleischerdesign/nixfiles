# Two shipped OpenClaw defects are repaired in the dist bundle until upstream
# covers them:
#
# 1. A private-repo chat on a session worker fails with
#    `Failed to prepare skill resources: ... error=hardlink: hardlinked path not allowed | INVALID_BUNDLE`
#    because `auto-optimise-store` hardlinks identical skill files across OpenClaw
#    store paths, and the worker skill bundler rejects every hardlinked file.
#    nix-openclaw already patches plugin and Control UI hardlink decisions; this
#    overlay adds the missing skill-tree decision. The store is immutable and
#    content-addressed, so a hardlink there aliases the same read-only bytes;
#    mutable skill roots keep the upstream rejection.
#
# 2. A subagent spawn from a repository-session worker resolves its managed
#    worktree from the agent workspace because the parent carries only
#    `repositoryWorkspaceId`. Base-ref discovery then runs `git ls-remote origin`
#    in an unrelated repository: it fails when that workspace has no remote, and
#    would build a worktree of the wrong repository when it has one. The parent's
#    checkout exists only on the paired node, so the spawn is refused with an
#    actionable message before any workspace is resolved.
#
# The wrapper runs nix-openclaw's dist patch first, then each fleet step. Delete
# this overlay when upstream applies the same decisions.
{ inputs }:
_final: prev:
let
  openclaw = inputs.openclaw.packages.${prev.stdenv.hostPlatform.system}.openclaw-gateway;
in
{
  openclaw-gateway = openclaw.overrideAttrs (previous: {
    env = (previous.env or { }) // {
      OPENCLAW_UPSTREAM_PATCH_NPM_DIST_SCRIPT = previous.env.OPENCLAW_PATCH_NPM_DIST_SCRIPT;
      OPENCLAW_PATCH_NPM_DIST_SCRIPT = "${./patch-openclaw-npm-dist.mjs}";
      OPENCLAW_SKILL_HARDLINK_PATCH = "${./patch-skill-hardlinks.mjs}";
      OPENCLAW_SKILL_HARDLINK_POLICY = "${./nix-skill-hardlink-policy.mjs}";
      OPENCLAW_NODE_SPAWN_SOURCE_PATCH = "${./patch-node-spawn-source.mjs}";
      OPENCLAW_NODE_SPAWN_SOURCE_POLICY = "${./node-spawn-source-policy.mjs}";
    };
  });
}
