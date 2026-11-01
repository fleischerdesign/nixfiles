// Decide whether a skill tree may contain hardlinked files.
//
// The worker skill bundler rejects every hardlinked file, while `auto-optimise-store`
// hardlinks identical files across content-addressed Nix store outputs. The store is
// immutable and root-owned, so a hardlink there aliases the same read-only bytes; a
// mutable skill root keeps the upstream rejection.
//
// This is the same distinction OpenClaw already draws for plugin files in
// `shouldRejectHardlinkedPluginFiles`, with the ownership and writability checks the
// fleet applied to its earlier resource-hardlink policy. It is deliberately not a
// blanket `/nix/store` prefix check: a path that only looks like a store output, a
// writable output, or an output owned by another account stays rejected.
//
// The test hooks below (`env`, `storeRoot`, `statSync`, `realpathSync`) exist so the
// check can exercise ownership and path negatives without a privileged test user.
import fs from "node:fs";
import path from "node:path";

const DEFAULT_STORE_ROOT = "/nix/store";

export function resourceHardlinkPolicy(directory, options = {}) {
  const env = options.env ?? process.env;
  const storeRoot = options.storeRoot ?? DEFAULT_STORE_ROOT;
  const statSync = options.statSync ?? fs.statSync;
  const realpathSync = options.realpathSync ?? fs.realpathSync;

  if (env.OPENCLAW_NIX_MODE !== "1") return "reject";

  try {
    const canonicalStore = realpathSync(storeRoot);
    const canonical = realpathSync(directory);

    // Resolve both sides: a symlink in a mutable root that points into the store is
    // still immutable bytes, while a path spelled like a store output is not.
    if (canonical !== canonicalStore && !canonical.startsWith(`${canonicalStore}/`)) return "reject";
    const relative = canonical.slice(canonicalStore.length + 1);
    const outputMatch = /^[a-z0-9]{32}-[^/]+(?=\/|$)/.exec(relative);
    if (!outputMatch) return "reject";

    const store = statSync(canonicalStore);
    if (!store.isDirectory() || (store.mode & 0o002) !== 0) return "reject";
    // A group-writable store needs its native sticky-bit protection. Store ownership
    // is mapped to nobody inside Nix build sandboxes, so compare with the store
    // authority, not literal uid 0.
    if ((store.mode & 0o020) !== 0 && (store.mode & 0o1000) === 0) return "reject";

    const output = path.join(canonicalStore, outputMatch[0]);
    for (const candidate of new Set([output, canonical])) {
      const stat = statSync(candidate);
      if (!stat.isDirectory() || stat.uid !== store.uid || (stat.mode & 0o222) !== 0) return "reject";
    }
    return "allow";
  } catch {
    return "reject";
  }
}
