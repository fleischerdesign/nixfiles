// Resource reads retain their native containment, symlink and size guards. Only the hardlink
// decision differs for immutable Nix inputs, never for mutable state or uploaded resources.
import fs from 'node:fs';

export function resourceHardlinkPolicy(directory, env = process.env) {
  if (env.OPENCLAW_NIX_MODE !== '1') return 'reject';
  try {
    const canonical = fs.realpathSync(directory);
    const match = /^\/nix\/store\/[a-z0-9]{32}-[^/]+(?=\/|$)/.exec(canonical);
    if (!match) return 'reject';
    // Do not trust a path-shaped string or a mutable directory masquerading as a store output.
    const store = fs.statSync('/nix/store');
    if (!store.isDirectory() || (store.mode & 0o002) !== 0) return 'reject';
    // A group-writable store needs its native sticky-bit protection. Store ownership is mapped
    // to nobody inside Nix build sandboxes, so compare with the store authority, not literal uid 0.
    if ((store.mode & 0o020) !== 0 && (store.mode & 0o1000) === 0) return 'reject';
    for (const candidate of new Set([match[0], canonical])) {
      const stat = fs.statSync(candidate);
      if (!stat.isDirectory() || stat.uid !== store.uid || (stat.mode & 0o222) !== 0) return 'reject';
    }
    return 'allow';
  } catch {
    return 'reject';
  }
}
