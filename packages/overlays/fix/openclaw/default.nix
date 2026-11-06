# Local patch: the worker skill bundler rejects hardlinked Nix-store skill trees.
#
# `auto-optimise-store` gives every packaged SKILL.md nlink > 1, so a worker turn
# that bundles skills fails with INVALID_BUNDLE before any model call, although
# ordinary skill discovery already trusts immutable store roots. The patch
# forwards that existing trust decision to the bundle reader.
#
# The script is anchored by symbols, not by file name or line number, so a version
# bump keeps applying it; when an anchor disappears the build fails and names this
# overlay. Delete this directory and its flake.nix entry once upstream fixes the
# reader - the script refuses to run on an already-fixed package.
# Rationale and scope: docs/operations.md.
# The npm package sets `dontFixup`, so the patch runs at the end of the install
# phase instead of in postFixup.
_final: prev: {
  openclaw-gateway = prev.openclaw-gateway.overrideAttrs (previous: {
    installPhase = ''
      ${previous.installPhase}
      ${prev.nodejs}/bin/node ${./allow-nix-store-skill-bundle-hardlinks.mjs} \
        "$out/lib/node_modules/openclaw"
    '';
  });
}
