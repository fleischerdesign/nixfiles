# A private-repo chat on a session worker fails with
# `Failed to prepare skill resources: ... error=hardlink: hardlinked path not allowed | INVALID_BUNDLE`
# because `auto-optimise-store` hardlinks identical skill files across OpenClaw
# store paths, and the worker skill bundler rejects every hardlinked file.
#
# A `sessions_spawn` from a visible repository session placed on a node also
# fails to inherit that repository: the placed spawn forces `worktree: true` with
# no project or worktree source, so the child falls back to the Gateway's default
# checkout. The same dist patch adds the missing repository-parent branch. It
# captures the parent's *live* working tree under the parent turn's existing
# placement claim - quiesce, reconcile and the double-manifest final fence - and
# publishes it as an isolated child checkpoint. It never claims or accepts a
# result for the parent and never changes the parent's accepted checkpoint. The
# hidden subagent path is refused explicitly because it has no placed child
# workspace to seed.
#
# nix-openclaw already patches plugin and Control UI hardlink decisions; this overlay
# adds the missing skill-tree decision to the same dist-patch phase. The store is
# immutable and content-addressed, so a hardlink there aliases the same read-only
# bytes; mutable skill roots keep the upstream rejection. Delete this overlay when
# upstream applies the same distinction to `readSkillBundleTree` and inherits a
# repository workspace from a placed parent for spawned children.
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
      OPENCLAW_SKILL_HARDLINK_POLICY = "${./nix-skill-hardlink-policy.mjs}";
    };
  });
}
