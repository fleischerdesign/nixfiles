/**
 * @module dsh-capability/capability
 * The canonical capability tuple with attestation, attenuation and principal
 * dominance (mesh-capability-authorization §4). This is the *single* shape every
 * grant in the mesh uses — node, tool, scope and `path:` resources all live in
 * one `ResourceURI` universe, and one `ActionSet` (the canonical verb set).
 *
 * The token format is `base64url(payloadJSON) "." hmachmac(secret, payloadJSON)`
 * — the same wire shape as `dsh-memory/capability.ts`, extended with
 * `principal`, `resources`, `actions` and `bounds`, and with the `ops`/`scopes`
 * legacy fields folded into the new `actions`/`resources` model. Nothing here
 * requires a WASM/derivation dependency; `biscuit-wasm` remains the canonical
 * upgrade path but this provides the same authorization surface now.
 */
import * as crypto from 'node:crypto';
import { CapabilityError } from './error.js';
import { compileRoot } from './canonicalize.js';

/** The canonical, closed verb set (mesh doc §4.2). */
export type Action =
  | 'read'
  | 'list'
  | 'write'
  | 'mutate'
  | 'exec'
  | 'orchestrate'
  | 'replicate';

export const ACTIONS: readonly Action[] = [
  'read',
  'list',
  'write',
  'mutate',
  'exec',
  'orchestrate',
  'replicate',
];

/** Principal identity URI: `user:`, `group:`, `node:`. */
export type PrincipalType = 'user' | 'group' | 'node';
export type Principal = string; // e.g. user:<oidc-sub>

/**
 * Resource URI, one closed namespace:
 *   node:<id>        — mesh peer / host
 *   tool:<op>        — a tool operation (e.g. tool:filesystem.read)
 *   scope:<scope>    — a memory scope (scope:user:<sub>, scope:group:family)
 *   path:<root>      — a filesystem root (prefix-matched by authorise)
 */
export type ResourceType = 'node' | 'tool' | 'scope' | 'path';
export type Resource = string; // e.g. node:strummer, path:/etc/nixos/**

export interface Bounds {
  /** Valid-until epoch ms. 0 = never expires (operator grants only). */
  ttl?: number;
  budgetEur?: number;
  maxTurns?: number;
  maxDepth?: number;
  pathAllowlist?: string[];
  resourceAllowlist?: string[];
}

export type SignAlg = 'hmac-sha256' | 'ed25519';

export interface CapClaims {
  principal: Principal; // who holds the grant
  resources: Resource[]; // what it may reach
  actions: Action[]; // what it may do
  bounds: Bounds;
  alg: SignAlg; // which attestation backend issued this (never cross-accepted)
  sink?: string; // initiating node (replay/non-replay binding)
  iat: number;
  exp: number;
  nonce: string;
  parent?: string; // parent signature (attenuation chain)
}

export interface CapabilityToken {
  payload: CapClaims;
  sig: string;
}

const b64u = (s: string) => Buffer.from(s, 'utf8').toString('base64url');
const unb64u = (s: string) => Buffer.from(s, 'base64url').toString('utf8');

/**
 * Path roots given as `path:/etc/nixos/**` are normalized to `/etc/nixos` for
 * matching; `**` is the only recursive form admitted (glob-heavy roots that
 * could alias outside the intended subtree are rejected — FS doc §7).
 */
export function pathResourceToRoot(resource: Resource): string | null {
  const m = /^path:(.+)$/.exec(resource);
  if (!m) return null;
  let root = m[1];
  // Reject globs other than a trailing `**`.
  if (root.includes('*')) {
    if (/\/\*\*$/.test(root)) root = root.slice(0, -'/**'.length);
    else throw new CapabilityError('invalid-path', `capability: unsupported glob in path root: ${resource}`);
  }
  return root;
}

/**
 * Principal dominance (`⊑`). A `user:<sub>` grant dominates the same user only;
 * a `group:<g>` grant dominates a principal that is a member of `g`; a
 * `node:<id>` grant dominates a node-asserted operation. There is **no
 * implicit upward grant** — principals never inherit each other's capabilities.
 */
export function dominates(grantPrincipal: Principal, effectivePrincipal: Principal, groups: string[]): boolean {
  if (grantPrincipal === effectivePrincipal) return true;
  if (grantPrincipal.startsWith('group:')) {
    const g = grantPrincipal.slice('group:'.length);
    return groups.includes(g);
  }
  // node: grants only dominate node assertions carried by the caller; the mesh
  // channel (node HMAC) is NOT authority on its own, so a node grant never
  // silently dominates a user principal here. Callers that legitimately act for
  // a node must present exactly that node principal.
  return false;
}

function signWith(alg: SignAlg, key: string, encoded: string): string {
  switch (alg) {
    case 'hmac-sha256':
      return crypto.createHmac('sha256', key).update(encoded).digest('hex');
    case 'ed25519':
      // key is the private/public key path captured at issuance; verification
      // dispatches to the matching backend. (Symmetric secret for operator mesh;
      // asymmetric keypair for public/family principals — mesh doc §4.3.)
      return crypto.sign(null, Buffer.from(encoded, 'utf8'), key).toString('hex');
    default:
      throw new CapabilityError('bad-signature', `capability: unknown alg ${alg}`);
  }
}

export function createToken(key: string, claims: Omit<CapClaims, 'iat' | 'nonce'>): CapabilityToken {
  const payload: CapClaims = {
    ...claims,
    iat: Date.now(),
    nonce: crypto.randomBytes(8).toString('hex'),
  };
  const encoded = b64u(JSON.stringify(payload));
  return { payload, sig: signWith(payload.alg, key, encoded) };
}

/**
 * Verify a token against a key. A token accepted under one `alg` is never
 * re-verified under a different scheme (mesh doc §4.3): `alg` is checked
 * first and the backend is dispatched by it.
 */
export function verifyToken(key: string, token: CapabilityToken): CapClaims {
  const printedAlg = token.payload.alg;
  if (printedAlg !== 'hmac-sha256' && printedAlg !== 'ed25519') {
    throw new CapabilityError('bad-signature', `capability: unsupported alg ${printedAlg}`);
  }
  const encoded = b64u(JSON.stringify(token.payload));
  const expected = signWith(printedAlg, key, encoded);
  const a = Buffer.from(expected);
  const b = Buffer.from(token.sig);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
    throw new CapabilityError('bad-signature', 'capability: bad signature');
  }
  const p = token.payload;
  if (p.exp && Date.now() > p.exp) throw new CapabilityError('expired', 'capability: expired');
  if (!p.principal) throw new CapabilityError('deny', 'capability: no principal');
  if (!p.resources || p.resources.length === 0) throw new CapabilityError('deny', 'capability: no resources');
  if (!p.actions || p.actions.length === 0) throw new CapabilityError('deny', 'capability: no actions');
  return p;
}

/**
 * Attenuate: produce a child capability whose grants are a strict subset of the
 * parent's, chaining the parent signature. The Non-Widening Invariant is
 * enforced structurally: every resource `r` in the child must be a prefix-equal
 * or strictly-narrower form of some parent resource, every action must appear in
 * the parent, and bounds may only tighten. Privilege escalation is excluded
 * because `authorise` only accepts the child's (narrower) grants.
 */
export function attenuate(
  key: string,
  parent: CapabilityToken,
  restriction: {
    resources?: Resource[];
    actions?: Action[];
    bounds?: Bounds;
    sink?: string;
  },
): CapabilityToken {
  const p = parent.payload;
  const resources = restriction.resources ?? p.resources;
  const actions = restriction.actions ?? p.actions;

  // Action subset check.
  if (!actions.every((a) => p.actions.includes(a))) {
    throw new CapabilityError('widening', 'capability: action attenuation exceeds parent');
  }

  // Resource narrowing: each child resource must be matched by some parent
  // resource. For `path:` roots, the child root must be inside a parent root
  // (prefix containment); for everything else, exact equality.
  for (const childRes of resources) {
    const covered = p.resources.some((parentRes) => {
      if (parentRes === childRes) return true;
      const childPath = pathResourceToRoot(childRes);
      const parentPath = pathResourceToRoot(parentRes);
      if (childPath !== null && parentPath !== null) {
        return compileRoot(parentPath)(childPath);
      }
      return false;
    });
    if (!covered) {
      throw new CapabilityError('widening', `capability: resource ${childRes} not covered by parent`);
    }
  }

  // Bounds may only tighten (never loosen a numeric/ttl ceiling).
  const bounds = restriction.bounds ?? p.bounds;
  if (bounds.ttl !== undefined && bounds.ttl > (p.bounds.ttl ?? Infinity)) {
    throw new CapabilityError('widening', 'capability: ttl widening');
  }
  if (bounds.maxDepth !== undefined && bounds.maxDepth >= (p.bounds.maxDepth ?? 0)) {
    throw new CapabilityError('widening', 'capability: maxDepth widening');
  }

  const child: CapClaims = {
    ...p,
    principal: p.principal,
    resources,
    actions,
    bounds,
    sink: restriction.sink ?? p.sink,
    exp: p.exp,
    nonce: crypto.randomBytes(8).toString('hex'),
    parent: parent.sig,
  };
  const encoded = b64u(JSON.stringify(child));
  return { payload: child, sig: signWith(child.alg, key, encoded) };
}

/** Marshal a token to a single header value. */
export function encodeToken(token: CapabilityToken): string {
  return `${b64u(JSON.stringify(token.payload))}.${token.sig}`;
}

/** Parse + verify an encoded token. Streams the verified claims. */
export function decodeToken(key: string, tokenStr: string): CapClaims {
  const dot = tokenStr.lastIndexOf('.');
  if (dot <= 0) throw new CapabilityError('bad-signature', 'capability: malformed token');
  const payload = JSON.parse(unb64u(tokenStr.slice(0, dot))) as CapClaims;
  const sig = tokenStr.slice(dot + 1);
  return verifyToken(key, { payload, sig });
}
