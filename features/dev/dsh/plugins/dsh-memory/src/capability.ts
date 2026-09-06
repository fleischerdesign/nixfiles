/**
 * @module dsh-memory/capability
 * Zero-Trust capability tokens (wasm-free). Replaces bare per-peer HMAC with a
 * self-contained, attenuable, expiring capability carrying explicit tenant +
 * scope + operation grants. Semantically aligned with Biscuit (formal-foundations
 * §5): a signed, caveated capability; native `biscuit-wasm` is the canonical
 * upgrade path once vendorable, but these tokens provide the same
 * authorization surface without a WASM dependency.
 *
 * A token is `base64url(payloadJSON) "." hmacSHA256(secret, base64url(payloadJSON))`.
 * Attenuation produces a child token whose grants are a SUBSET of its parent's;
 * the parent signature is chained so a presenter must hold the parent capability.
 */
import * as crypto from 'node:crypto';

export interface CapClaims {
  iss: string;      // issuer node
  sub: string;      // tenantContext: "user:<u>" | "group:<g>"
  scopes: string[]; // granted scopes (subset-guarded on attenuation)
  ops: string[];    // granted operations (e.g. ["sync"])
  sink: string;     // target node the token is usable against
  iat: number;
  exp: number;
  nonce: string;    // replay-protection
  parent?: string;  // parent token signature (attenuation chain)
}

export interface CapabilityToken {
  payload: CapClaims;
  sig: string;
}

const b64u = (s: string) => Buffer.from(s, 'utf8').toString('base64url');
const unb64u = (s: string) => Buffer.from(s, 'base64url').toString('utf8');

function sign(secret: string, encoded: string): string {
  return crypto.createHmac('sha256', secret).update(encoded).digest('hex');
}

export function createToken(secret: string, claims: Omit<CapClaims, 'iat' | 'nonce'>): CapabilityToken {
  const now = Date.now();
  const payload: CapClaims = {
    ...claims,
    iat: now,
    nonce: crypto.randomBytes(8).toString('hex'),
  };
  const encoded = b64u(JSON.stringify(payload));
  const sig = sign(secret, encoded);
  return { payload, sig };
}

/**
 * Verify a token. Returns the claims on success, throws on any failure.
 * Replay protection is enforced by the caller (must persist `nonce`).
 */
export function verifyToken(secret: string, token: CapabilityToken): CapClaims {
  const encoded = b64u(JSON.stringify(token.payload));
  const expected = sign(secret, encoded);
  const a = Buffer.from(expected);
  const b = Buffer.from(token.sig);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
    throw new Error('Capability: bad signature');
  }
  const p = token.payload;
  if (p.exp > 0 && Date.now() > p.exp) throw new Error('Capability: expired');
  if (!p.scopes || p.scopes.length === 0) throw new Error('Capability: no scopes granted');
  if (!p.ops || p.ops.length === 0) throw new Error('Capability: no ops granted');
  return p;
}

/**
 * Attenuate: create a child token whose grants are a strict subset of the
 * parent's. Scope/op sets must be subsets; the tenant (`sub`) must be equal.
 * The child chains to the parent signature, so a verifier can enforce that the
 * presenter actually holds the parent capability.
 */
export function attenuate(secret: string, parent: CapabilityToken, restriction: Partial<Pick<CapClaims, 'scopes' | 'ops' | 'sink'>>): CapabilityToken {
  const p = parent.payload;
  const scopes = restriction.scopes ?? p.scopes;
  const ops = restriction.ops ?? p.ops;
  if (!scopes.every((s) => p.scopes.includes(s))) throw new Error('Capability: scope attenuation exceeds parent');
  if (!ops.every((o) => p.ops.includes(o))) throw new Error('Capability: op attenuation exceeds parent');
  const child: CapClaims = {
    ...p,
    scopes,
    ops,
    sink: restriction.sink ?? p.sink,
    parent: parent.sig,
  };
  const encoded = b64u(JSON.stringify(child));
  return { payload: child, sig: sign(secret, encoded) };
}

/** Marshal a token to a single header value. */
export function encodeToken(token: CapabilityToken): string {
  return `${b64u(JSON.stringify(token.payload))}.${token.sig}`;
}

/** Parse + verify an encoded token string. */
export function decodeToken(secret: string, tokenStr: string): CapClaims {
  const dot = tokenStr.lastIndexOf('.');
  if (dot <= 0) throw new Error('Capability: malformed token');
  const payload = JSON.parse(unb64u(tokenStr.slice(0, dot)));
  const sig = tokenStr.slice(dot + 1);
  return verifyToken(secret, { payload, sig });
}
