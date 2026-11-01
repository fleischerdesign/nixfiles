# A private-repo chat on a session worker fails with
# `Failed to prepare skill resources: ... error=hardlink: hardlinked path not allowed | INVALID_BUNDLE`
# because `auto-optimise-store` hardlinks identical skill files across OpenClaw
# store paths, and the worker skill bundler rejects every hardlinked file.
#
# nix-openclaw already patches plugin and Control UI hardlink decisions; this overlay
# adds the missing skill-tree decision to the same dist-patch phase. The store is
# immutable and content-addressed, so a hardlink there aliases the same read-only
# bytes; mutable skill roots keep the upstream rejection. Delete this overlay when
# upstream applies the same distinction to `readSkillBundleTree`.
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
