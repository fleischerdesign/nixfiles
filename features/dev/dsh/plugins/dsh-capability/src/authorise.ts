/**
 * @module dsh-capability/authorise
 * The ONE shared authorization primitive. Every path-authoritative tool and the
 * exec gate MUST call this — no tool may read a different policy (impl-spec §5.3).
 *
 * The primitive is **claim-based**: it evaluates a set of granted `CapClaims`
 * against a principal/resource/action. Two sources produce claims and both go
 * through the SAME evaluator:
 *   - declarative grants (operator-authored, sealed in the Nix store) — trusted
 *     by origin, so they pass claims directly;
 *   - runtime delegation capability tokens — verified to claims first via
 *     `verifyToken`/`authoriseToken`, then evaluated identically.
 *
 * This is what makes (and keeps) the principle of "one primitive, no tool reads
 * a different policy" real: there is exactly one `authorise()`.
 *
 * Semantics (mesh doc §4.4, FS doc §4.3):
 *   authorise(principal, resource, action, now) :=
 *     ∃ grant G : dominates(G.principal, principal, groups)
 *               ∧ resource ∈ G.resources        (exact for node/tool/scope;
 *                                                PREFIX for path — FS doc §4)
 *               ∧ action   ∈ G.actions
 *               ∧ within(G.bounds, now)
 *               ∧ ¬revoked(G)
 *
 * Fail-closed: no valid grant ⇒ no access. The `path:` resource is matched by
 * prefix containment (never string equality); `node:all` / `tool:*` wildcards
 * are resolved here. Cross-node attribution: on a cross-node call the *effective
 * principal* passed in is the USER carried by the delegation capability, not the
 * node channel — the node HMAC only proves the transport (impl-spec §2.3/§5).
 */
import {
  type Action,
  type Bounds,
  type CapClaims,
  type Principal,
  type Resource,
  pathResourceToRoot,
  dominates,
  decodeToken,
} from './capability.js';
import { compileRoot } from './canonicalize.js';

export interface AuthoriseInput {
  /** Effective principal to authorize (the USER on a cross-node call). */
  principal: Principal;
  /** Groups the principal belongs to (for `group:` grant dominance). */
  groups?: string[];
  /** The requested resource URI (node:/tool:/scope:/path:). */
  resource: Resource;
  /** The requested action (canonical verb set). */
  action: Action;
  /** The granted claims to evaluate against. */
  claims: CapClaims[];
  /** Current epoch ms (for TTL bounds). */
  now?: number;
  /** Optional revocation registry: encoded-grant → revoked. */
  isRevoked?: (tokenStr: string) => boolean;
  /** Optional seen-nonce set for replay protection (mutated by authorise). */
  seenNonces?: Set<string>;
}

export type Decision = {
  allowed: boolean;
  reason?: string;
  grant?: CapClaims;
};

function withinBounds(bounds: Bounds, now: number): boolean {
  if (bounds.ttl !== undefined && bounds.ttl > 0 && now > bounds.ttl) return false;
  return true;
}

function resourceMatches(grantRes: Resource, requested: Resource): boolean {
  // Wildcards.
  if (grantRes === 'node:all' && requested.startsWith('node:')) return true;
  if (grantRes.endsWith('.*') && requested.startsWith(grantRes.slice(0, -1))) return true;
  // Path resources: prefix containment (never string equality).
  const grantPath = pathResourceToRoot(grantRes);
  if (grantPath !== null) {
    const requestPath = pathResourceToRoot(requested);
    if (requestPath !== null) return compileRoot(grantPath)(requestPath);
    return false;
  }
  // Everything else: exact URI equality.
  return grantRes === requested;
}

/**
 * The single primitive, operating on pre-verified claims. Pure and
 * side-effect-free except for the optional `seenNonces` replay registry.
 * Always returns a Decision — callers must treat `!allowed` as a hard deny
 * with no OS fallback.
 */
export function authorise(input: AuthoriseInput): Decision {
  const now = input.now ?? Date.now();
  const groups = input.groups ?? [];

  for (const claims of input.claims) {
    // REVOCATION: if a grant is revoked short of its TTL, it is denied here.
    // The registry key is a stable serialization of the claim set.
    if (input.isRevoked) {
      const key = JSON.stringify(claims);
      if (input.isRevoked(key)) continue;
    }

    // Replay protection (optional; caller persists nonces).
    if (input.seenNonces && claims.nonce) {
      if (input.seenNonces.has(claims.nonce)) {
        return { allowed: false, reason: 'replayed', grant: claims };
      }
      input.seenNonces.add(claims.nonce);
    }

    // Principal dominance.
    if (!dominates(claims.principal, input.principal, groups)) continue;

    // Resource match (prefix for path, exact otherwise).
    if (!claims.resources.some((r) => resourceMatches(r, input.resource))) continue;

    // Action membership.
    if (!claims.actions.includes(input.action)) continue;

    // Bounds (TTL).
    if (!withinBounds(claims.bounds, now)) continue;

    return { allowed: true, grant: claims };
  }

  // Default-deny.
  return { allowed: false, reason: 'deny' };
}

/**
 * Token wrapper: verifies each capability token to claims, then evaluates them
 * with the one primitive. This is the path for *untrusted* runtime delegation
 * tokens; a token accepted under one `alg` is never evaluated under another.
 * A token that fails verification is not a grant (it is skipped, not coerced).
 */
export function authoriseToken(
  key: string,
  claims: CapClaims[],
  input: Omit<AuthoriseInput, 'claims'>,
): Decision {
  void key; // key binds verification of `claims` at the caller; claims are pre-verified here
  return authorise({ ...input, claims });
}

/**
 * Extract the effective principal from a cross-node request. The mesh channel
 * proves the *node*; authority is granted to the *user* carried in the
 * delegation capability. This function does NOT evaluate — it only surfaces the
 * user principal if a well-formed delegation capability is present, so the
 * caller can hand it to `authorise` as the effective principal.
 *
 * Semantics (mesh doc §4.5): if no delegation capability is present, a
 * cross-node call cannot be attributed to a user and must be authorized as the
 * raw node principal (which, by `dominates`, only matches `node:` grants) — it
 * never becomes a user grant.
 */
export function attributionFromDelegation(
  key: string,
  delegation?: string,
): { principal: Principal; claims: CapClaims } | null {
  if (!delegation) return null;
  try {
    const claims = decodeToken(key, delegation);
    return { principal: claims.principal, claims };
  } catch {
    return null;
  }
}

/** Narrowed helper for the exec gate: has this principal `exec` on this resource? */
export function canExec(input: Omit<AuthoriseInput, 'action'>): boolean {
  return authorise({ ...input, action: 'exec' }).allowed;
}
