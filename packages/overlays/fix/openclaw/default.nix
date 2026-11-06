# Local patches for the openclaw-gateway package:
#
# 1. The worker skill bundler rejects hardlinked Nix-store skill trees.
# 2. A worker turn reads session capability metadata outside a prepared scope.
#
# Both replace behaviour the local (non-worker) path already has, and both are
# anchored by symbols instead of file names or line numbers, so a version bump
# keeps applying them. When an anchor disappears the build fails and names this
# overlay; an already-patched package fails the same way, so neither patch can
# silently become a no-op.
#
# The npm package sets `dontFixup`, so the patches run at the end of the install
# phase instead of in postFixup.
#
# Rationale and scope: docs/operations.md. Delete this directory and its
# flake.nix entry once upstream covers both behaviours.
_final: prev: {
  openclaw-gateway = prev.openclaw-gateway.overrideAttrs (previous: {
    installPhase = ''
      ${previous.installPhase}
      ${prev.nodejs}/bin/node ${./allow-nix-store-skill-bundle-hardlinks.mjs} \
        "$out/lib/node_modules/openclaw"
      ${prev.nodejs}/bin/node ${./prepare-worker-capability-reads.mjs} \
        "$out/lib/node_modules/openclaw"
      ${prev.nodejs}/bin/node ${./trace-capability-read.mjs} \
        "$out/lib/node_modules/openclaw"
    '';
  });
}
