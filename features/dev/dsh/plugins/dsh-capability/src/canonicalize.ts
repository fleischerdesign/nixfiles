/**
 * @module dsh-capability/canonicalize
 * Deterministic, fail-closed path canonicalization for the path-capability
 * layer. This is the *only* place the filesystem dimension decides how a
 * requested path is normalized before it is matched against granted roots
 * (filesystem-capability-layer §4.1).
 *
 * The security invariant: a path that cannot be canonicalized is **rejected
 * outright** — never coerced, never "best-effort" resolved. Symlink resolution
 * (which must happen against the live filesystem with `realpath`) is a separate,
 * explicit step performed by the tool layer *before* `authorise`, so this module
 * stays pure, deterministic and unit-testable. The lexical rules below are the
 * mandatory pass that both the pure matcher and the fs-resolved real path are
 * pushed through.
 *
 * Rules (see FS doc §4.1):
 *   1. reject embedded NUL / control bytes,
 *   2. require an absolute path (`/`-rooted) — capability roots are always
 *      absolute,
 *   3. condense `.` and `..` segments lexically; an un-condensable `..` (one
 *      that would pop above the mount root) is an escape and is rejected,
 *   4. device nodes / FIFOs are not special here (path form only); the caller
 *      enforces device-node access via the action (`exec`) if it grants it.
 *
 * Empty paths and whitespace-only paths are rejected (they cannot name a real
 * object and are common in canonicalization-gap bugs).
 */
import { CapabilityError } from './error.js';

const NUL = 0x00;

function isControl(b: number): boolean {
  // NUL and C0 controls (0x00..0x1f) are never valid in a path segment.
  return b < 0x20;
}

/**
 * Canonicalize an absolute, lexically-normalized path.
 *
 * Returns the canonical absolute path (no leading `.`/`..`, no repeated
 * slashes, no trailing slash unless the root). Throws `CapabilityError` with
 * `invalid-path` on any reason the path cannot be canonically described.
 */
export function canonicalize(input: string): string {
  if (typeof input !== 'string' || input.length === 0) {
    throw new CapabilityError('invalid-path', 'canonicalize: empty path');
  }

  // 1. Reject control bytes block-wise (fast) and byte-wise (authoritative).
  for (let i = 0; i < input.length; i += 1) {
    const c = input.charCodeAt(i);
    if (c === NUL || c < 0x20) {
      throw new CapabilityError('invalid-path', `canonicalize: control byte at ${i}`);
    }
  }

  // 2. Must be absolute.
  if (!input.startsWith('/')) {
    throw new CapabilityError('invalid-path', `canonicalize: not absolute: ${input}`);
  }

  // 3. Condense "." / ".." — but reject a `..` that would pop above the root.
  const out: string[] = [];
  const raw = input.split('/');
  for (const seg of raw) {
    if (seg === '' || seg === '.') continue; // "" from //, or "."
    if (seg === '..') {
      if (out.length === 0) {
        // Popping the mount root (leading ".." or "/..") — an escape or an
        // unresolvable path. Fail closed.
        throw new CapabilityError('invalid-path', `canonicalize: traversal escapes root: ${input}`);
      }
      out.pop();
      continue;
    }
    out.push(seg);
  }

  const canonical = '/' + out.join('/');
  // Root "/" and paths that collapse to "/" are valid but never grant anything
  // by themselves (a grant over "/" is the whole-FS grant the model forbids by
  // default; still representable, but `authorise` treats the empty grants set
  // with default-deny).
  return canonical === '' ? '/' : canonical;
}

/**
 * Strict prefix containment — the core of the prefix automaton predicate
 * `matches(path, root)` (FS doc §4.2). `path` is *equal to* or *strictly
 * inside* `root`.
 *
 * Boundary safety is essential: `/etc/foo` is inside `/etc`, but `/etcd` is
 * NOT — a naive `startsWith` would leak the sibling. The separator-boundary
 * check is what prevents that.
 */
export function isWithinRoot(root: string, path: string): boolean {
  const r = canonicalize(root);
  const p = canonicalize(path);
  if (r === '/') return p === '/'; // whole-FS root never matcher-implicitly-widens; rely on explicit grants
  if (p === r) return true;
  if (!p.startsWith(r)) return false;
  // Require a path-separator boundary strictly after the root.
  return p.charAt(r.length) === '/';
}

/**
 * Cross-boundary detection (FS doc §4.2 `isBoundary`). A path is *on the
 * boundary* of a root when it is the root itself (rename/delete of the root,
 * or a write that targets the root's own entry). Such operations are the ones
 * that must be authorized against a *parent* grant, never implicitly by the
 * subtree grant.
 */
export function isRootEntry(root: string, path: string): boolean {
  return canonicalize(path) === canonicalize(root);
}

/**
 * The default-deny matcher used by `authorise` for `path:` resources.
 * Returns the grant that covers the requested path+action, or `null`.
 *
 * This is deliberately a *pure predicate* over already-resolved real paths; the
 * tool layer resolves symlinks (via the fs-aware wrapper in `runtimePath.js`)
 * before calling it, so a symlink that resolves outside a granted root is
 * already the *resolved* path and fails `matches` (V5), while a `..` in the
 * raw request is removed or rejected by `canonicalize` (V6).
 */
export interface PathGrant {
  root: string;
  /** Matcher compiled from the grant's `path:` resource. */
  matches(p: string): boolean;
}

/**
 * Compile a single path root into a checked predicate. Roots are always
 * absolute and canonical; a `**` suffix is the only glob form the model
 * admits (recursive subtree), and it is normalized away by the caller into the
 * plain prefix here.
 */
export function compileRoot(root: string): (path: string) => boolean {
  const canonicalRoot = canonicalize(root);
  return (path: string) => isWithinRoot(canonicalRoot, path);
}
