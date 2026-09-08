/**
 * @module dsh-auth/oidc-flow
 * Interactive OpenID Connect (Authorization Code + PKCE) flow for dsh-auth.
 * Provides the pure, testable crypto primitives (PKCE, ID-token RS256/JWKS
 * verification, authorize-URL construction) and a short-lived flow store for
 * state/nonce/code_verifier. The HTTP token exchange and JWKS retrieval use an
 * injectable fetch (default node:https) so they can be tested without a live IdP.
 */
import * as crypto from 'node:crypto';
import * as https from 'node:https';
import * as http from 'node:http';
import * as URL from 'node:url';

export interface OidcFlowConfig {
  issuer: string;
  clientId: string;
  clientSecret?: string;
  redirectUri: string;
  scopes: string[];
  logoutUri?: string; // end_session endpoint (optional, validated separately)
}

export interface PkcePair { verifier: string; challenge: string; method: 'S256'; }

/** RFC 7636 PKCE: verifier = 64 random bytes (base64url), challenge = S256(verifier). */
export function pkcePair(): PkcePair {
  const verifier = crypto.randomBytes(64).toString('base64url');
  const challenge = crypto.createHash('sha256').update(verifier).digest('base64url');
  return { verifier, challenge, method: 'S256' };
}

export function b64url(s: Buffer | string): string {
  return Buffer.from(s).toString('base64url').replace(/=+$/g, '');
}

/** Base64url-decode a JWT part to bytes. */
export function unb64url(s: string): Buffer {
  const pad = s.length % 4 === 0 ? '' : '='.repeat(4 - (s.length % 4));
  return Buffer.from(s.replace(/-/g, '+').replace(/_/g, '/') + pad, 'base64');
}

/** Decode (without verifying) the payload claims of a JWT. */
export function jwtClaims(idToken: string): Record<string, unknown> {
  const parts = idToken.split('.');
  if (parts.length !== 3) throw new Error('oidc: malformed id_token');
  const json = unb64url(parts[1]).toString('utf8');
  return JSON.parse(json) as Record<string, unknown>;
}

/** Build the authorize redirect URL (Authorization Code + PKCE). */
export function buildAuthorizeUrl(
  cfg: OidcFlowConfig,
  opts: { state: string; nonce: string; challenge: string; method: string },
): string {
  const u = new URL.URL(cfg.issuer + '/authorize');
  u.searchParams.set('response_type', 'code');
  u.searchParams.set('client_id', cfg.clientId);
  u.searchParams.set('redirect_uri', cfg.redirectUri);
  u.searchParams.set('state', opts.state);
  u.searchParams.set('nonce', opts.nonce);
  u.searchParams.set('code_challenge', opts.challenge);
  u.searchParams.set('code_challenge_method', opts.method);
  u.searchParams.set('scope', cfg.scopes.join(' '));
  return u.toString();
}

/** Verify an RS256-signed JWT (by kid) against a JWKS key set; enforce iss/aud/exp/nonce. */
export function verifyIdToken(opts: {
  idToken: string;
  jwks: Array<{ kid?: string; kty: string; n: string; e: string; alg?: string }>;
  issuer: string;
  audience: string;
  nonce?: string;
  nowMs?: number;
}): Record<string, unknown> {
  const claims = jwtClaims(opts.idToken);
  const header = JSON.parse(unb64url(opts.idToken.split('.')[0]).toString('utf8')) as { alg?: string; kid?: string };

  // 1. Signature (RS256 against the matching JWK).
  const key = (header.kid ? opts.jwks.find((k) => k.kid === header.kid) : opts.jwks[0]) as any;
  if (!key || key.kty !== 'RSA') throw new Error('oidc: no matching RSA key');
  const signingInput = `${opts.idToken.split('.')[0]}.${opts.idToken.split('.')[1]}`;
  const signature = unb64url(opts.idToken.split('.')[2]);
  const publicKey = crypto.createPublicKey({
    key: { kty: 'RSA', n: key.n, e: key.e, alg: 'RS256' },
    format: 'jwk',
  });
  const ok = crypto.verify('RSA-SHA256', Buffer.from(signingInput), publicKey, signature);
  if (!ok) throw new Error('oidc: invalid id_token signature');

  // 2. Timestamp & claims.
  const now = Math.floor((opts.nowMs ?? Date.now()) / 1000);
  if (typeof claims.exp === 'number' && claims.exp < now) throw new Error('oidc: id_token expired');
  if (claims.iss !== opts.issuer) throw new Error('oidc: issuer mismatch');
  const aud = claims.aud;
  const audMatch = Array.isArray(aud) ? aud.includes(opts.audience) : aud === opts.audience;
  if (!audMatch) throw new Error('oidc: audience mismatch');
  if (opts.nonce && claims.nonce !== opts.nonce) throw new Error('oidc: nonce mismatch');
  return claims;
}

export interface FetchLike {
  (url: string, opts?: { method?: string; headers?: Record<string, string>; body?: string }): Promise<{ ok: boolean; status: number; json: () => Promise<any> }>;
}

function httpsFetch(url: string, opts: { method?: string; headers?: Record<string, string>; body?: string } = {}): Promise<{ ok: boolean; status: number; json: () => Promise<any> }> {
  return new Promise((resolve, reject) => {
    const u = new URL.URL(url);
    const lib = u.protocol === 'https:' ? https : http;
    const req = lib.request(
      { hostname: u.hostname, port: u.port || (u.protocol === 'https:' ? 443 : 80), path: u.pathname + u.search, method: opts.method || 'GET', headers: opts.headers },
      (res) => {
        let data = '';
        res.on('data', (d: Buffer) => { data += d; });
        res.on('end', () => {
          resolve({ ok: !!res.statusCode && res.statusCode >= 200 && res.statusCode < 300, status: res.statusCode || 0, json: async () => JSON.parse(data) });
        });
      },
    );
    req.on('error', reject);
    req.setTimeout(10000, () => { req.destroy(new Error('oidc: timeout')); });
    if (opts.body) req.write(opts.body);
    req.end();
  });
}

const DEFAULT_FETCH: FetchLike = (u, o) => httpsFetch(u, o as any) as any;

/** Authorization Code -> Token endpoint exchange (form-encoded). */
export async function exchangeCode(
  cfg: OidcFlowConfig,
  opts: { code: string; verifier: string; fetch?: FetchLike },
): Promise<{ access_token?: string; id_token?: string; refresh_token?: string; token_type?: string }> {
  const fetchFn = opts.fetch || DEFAULT_FETCH;
  const params = new URL.URLSearchParams();
  params.set('grant_type', 'authorization_code');
  params.set('code', opts.code);
  params.set('redirect_uri', cfg.redirectUri);
  params.set('client_id', cfg.clientId);
  params.set('code_verifier', opts.verifier);
  if (cfg.clientSecret) params.set('client_secret', cfg.clientSecret);
  const res = await fetchFn(`${cfg.issuer}/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: params.toString(),
  });
  const body = await res.json();
  if (!res.ok) throw new Error(`oidc: token exchange failed (${res.status}): ${JSON.stringify(body)}`);
  return body;
}

/** Retrieve + cache the issuer's JWKS (for ID-token signature verification). */
export async function fetchJwks(cfg: OidcFlowConfig, fetch?: FetchLike): Promise<Array<{ kid?: string; kty: string; n: string; e: string; alg?: string }>> {
  const fetchFn = fetch || DEFAULT_FETCH;
  const res = await fetchFn(`${cfg.issuer}/.well-known/jwks.json`);
  const body = await res.json();
  if (!res.ok) throw new Error('oidc: jwks fetch failed');
  return (body.keys || []) as Array<{ kid?: string; kty: string; n: string; e: string; alg?: string }>;
}

/**
 * Short-lived flow store binding `state` -> { nonce, verifier, redirectTo, expiresAt }.
 * Used to prevent CSRF (state), bind the ID token (nonce) and complete PKCE (verifier).
 */
export class OidcFlowStore {
  private store = new Map<string, { nonce: string; verifier: string; redirectTo: string; expiresAt: number }>();

  begin(ttlMs = 600_000): { state: string; nonce: string; verifier: string; challenge: string; redirectTo: string } {
    const state = crypto.randomBytes(16).toString('hex');
    const nonce = crypto.randomBytes(16).toString('hex');
    const pair = pkcePair();
    const redirectTo = '/';
    this.store.set(state, { nonce, verifier: pair.verifier, redirectTo, expiresAt: Date.now() + ttlMs });
    this.gc();
    return { state, nonce, verifier: pair.verifier, challenge: pair.challenge, redirectTo };
  }

  consume(state: string): { nonce: string; verifier: string; redirectTo: string } | null {
    const e = this.store.get(state);
    if (!e) return null;
    this.store.delete(state);
    if (e.expiresAt < Date.now()) return null;
    return e;
  }

  gc(): void {
    const now = Date.now();
    for (const [k, v] of this.store) if (v.expiresAt < now) this.store.delete(k);
  }
}
