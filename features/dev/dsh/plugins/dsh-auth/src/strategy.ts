import * as crypto from 'node:crypto';
import type { IncomingMessage } from 'node:http';
import type {
  AuthPluginConfig,
  UserIdentity,
  ClearanceLevel
} from './types.js';

export interface AuthStrategy {
  readonly name: string;
  canHandle(req: IncomingMessage, remoteIp: string): boolean;
  authenticate(req: IncomingMessage, remoteIp: string): Promise<UserIdentity | null>;
}

/**
 * 1. ForwardProxyStrategy (Authentik / Caddy / Traefik / NGINX)
 */
export class ForwardProxyStrategy implements AuthStrategy {
  readonly name = 'forward-proxy';

  constructor(private config: AuthPluginConfig) {}

  canHandle(req: IncomingMessage, remoteIp: string): boolean {
    const fp = this.config.forwardProxy;
    if (!fp || fp.enabled === false) return false;

    // Verify proxy IP
    const trusted = fp.trustedProxies || ['127.0.0.1', '::1'];
    const isTrusted = trusted.includes(remoteIp) || remoteIp === '127.0.0.1' || remoteIp === '::1';
    if (!isTrusted) return false;

    // Check user header existence
    const userHeader = fp.headerUser || 'x-authentik-username';
    return Boolean(req.headers[userHeader.toLowerCase()]);
  }

  async authenticate(req: IncomingMessage): Promise<UserIdentity | null> {
    const fp = this.config.forwardProxy || { enabled: true };
    const userHeader = (fp.headerUser || 'x-authentik-username').toLowerCase();
    const emailHeader = (fp.headerEmail || 'x-authentik-email').toLowerCase();
    const groupsHeader = (fp.headerGroups || 'x-authentik-groups').toLowerCase();

    const usernameRaw = req.headers[userHeader];
    const username = Array.isArray(usernameRaw) ? usernameRaw[0] : usernameRaw;
    if (!username) return null;

    const emailRaw = req.headers[emailHeader];
    const email = Array.isArray(emailRaw) ? emailRaw[0] : emailRaw;

    const groupsRaw = req.headers[groupsHeader];
    let groups: string[] = [];
    if (groupsRaw) {
      const groupsStr = Array.isArray(groupsRaw) ? groupsRaw[0] : groupsRaw;
      groups = groupsStr.split('|').map(g => g.trim()).filter(Boolean);
    }

    // Determine clearance level based on groups
    let clearance: ClearanceLevel = 'Restricted';
    const adminGroups = fp.adminGroups || ['authentik Admins', 'wheel', 'admin'];
    const memberGroups = fp.memberGroups || ['family', 'users', 'member'];

    if (groups.some(g => adminGroups.includes(g))) {
      clearance = 'Admin';
    } else if (groups.some(g => memberGroups.includes(g))) {
      clearance = 'Member';
    }

    return {
      id: `usr_${username}`,
      username,
      email: email || undefined,
      groups,
      clearance,
      provider: 'forward-proxy'
    };
  }
}

/**
 * 2. LoopbackStrategy (Desktop / Local CLI)
 */
export class LoopbackStrategy implements AuthStrategy {
  readonly name = 'loopback';

  constructor(private config: AuthPluginConfig) {}

  canHandle(req: IncomingMessage, remoteIp: string): boolean {
    const lb = this.config.loopback;
    if (lb && lb.enabled === false) return false;

    // Loopback IP only
    return remoteIp === '127.0.0.1' || remoteIp === '::1' || remoteIp === 'localhost';
  }

  async authenticate(_req: IncomingMessage): Promise<UserIdentity | null> {
    const lb = this.config.loopback;
    const username = lb?.defaultUser || process.env.USER || 'local';
    const clearance = lb?.defaultClearance || 'Admin';

    return {
      id: `usr_${username}`,
      username,
      groups: ['wheel'],
      clearance,
      provider: 'loopback'
    };
  }
}

/**
 * 3. PeerMeshStrategy (Node-to-Node HMAC authentication)
 */
export class PeerMeshStrategy implements AuthStrategy {
  readonly name = 'peer-mesh';

  constructor(private config: AuthPluginConfig) {}

  canHandle(req: IncomingMessage): boolean {
    const pm = this.config.peerMesh;
    if (!pm || pm.enabled === false) return false;

    return Boolean(req.headers['x-dsh-node'] && req.headers['x-dsh-signature'] && req.headers['x-dsh-timestamp']);
  }

  async authenticate(req: IncomingMessage): Promise<UserIdentity | null> {
    const pm = this.config.peerMesh;
    if (!pm?.clusterSecret) return null;

    const node = req.headers['x-dsh-node'] as string;
    const signature = req.headers['x-dsh-signature'] as string;
    const timestampStr = req.headers['x-dsh-timestamp'] as string;
    const timestamp = parseInt(timestampStr, 10);

    const now = Date.now();
    const allowedDrift = pm.allowedTimeDriftMs ?? 10000;
    if (isNaN(timestamp) || Math.abs(now - timestamp) > allowedDrift) {
      return null; // Clock drift or replay attack
    }

    // Verify HMAC-SHA256 signature (transport / node channel).
    const method = req.method || 'GET';
    const url = req.url || '/';
    const payload = `${method}:${url}:${timestampStr}:${node}`;
    const expectedSig = crypto.createHmac('sha256', pm.clusterSecret).update(payload).digest('hex');

    const expectedBuf = Buffer.from(expectedSig);
    const actualBuf = Buffer.from(signature);
    if (expectedBuf.length !== actualBuf.length || !crypto.timingSafeEqual(expectedBuf, actualBuf)) {
      return null;
    }

    // Cross-node principal attribution (mesh doc §4.5 / impl-spec §2.3). The node
    // HMAC proves the CHANNEL; authority is granted to the USER carried in the
    // delegation capability. When a valid `x-dsh-capability` is present, the
    // target evaluates the user principal — never the node as Admin.
    const delegation = req.headers['x-dsh-capability'] as string | undefined;
    if (delegation) {
      const resolved = verifyDelegationCapability(delegation, pm.clusterSecret, now);
      if (!resolved) return null; // invalid delegation ⇒ reject the call entirely
      // Act for the user principal, bounded by the capability's actions. An
      // `orchestrate` action is admin-equivalent; otherwise bounded to Member.
      const clearance: ClearanceLevel = resolved.actions.includes('orchestrate') ? 'Admin' : 'Member';
      return {
        id: `usr_${resolved.principal}`,
        username: resolved.principal,
        groups: ['mesh-users'],
        clearance,
        provider: 'peer-mesh',
      };
    }

    // No delegation capability: retain the existing peer behaviour (trust domain
    // A — shared-secret, equal-rights operator peers). Because this is only the
    // node channel, callers must NOT grant user scopes off it.
    return {
      id: `node_${node}`,
      username: `node:${node}`,
      groups: ['mesh-nodes'],
      clearance: 'Admin', // Peer nodes run with Admin capability under Task Contract constraints
      provider: 'peer-mesh'
    };
  }
}

/**
 * Verify a delegation capability (same wire format as dsh-capability:
 * `base64url(payloadJSON) "." hmacHex(secret, payloadJSON)`), extract the user
 * principal and actions, and reject anything that is not a `user:` principal.
 * A malformed/expired/wrongly-signed token is `null` (fail-closed).
 */
function verifyDelegationCapability(
  tokenStr: string,
  secret: string,
  now: number,
): { principal: string; actions: string[] } | null {
  const dot = tokenStr.lastIndexOf('.');
  if (dot <= 0) return null;
  const b64 = tokenStr.slice(0, dot);
  const sig = tokenStr.slice(dot + 1);
  let payload: any;
  try {
    payload = JSON.parse(Buffer.from(b64, 'base64url').toString('utf8'));
  } catch {
    return null;
  }
  if (typeof payload !== 'object' || payload === null) return null;

  // Verify signature under the SAME secret (operator mesh is symmetric-HMAC).
  const expected = crypto.createHmac('sha256', secret).update(b64).digest('hex');
  const a = Buffer.from(expected);
  const b = Buffer.from(sig);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null;

  // Expiry.
  if (payload.exp && payload.exp > 0 && now > payload.exp) return null;

  // Must be a USER principal (a node principal is never a delegation grant).
  const principal = payload.principal;
  if (typeof principal !== 'string' || !principal.startsWith('user:')) return null;

  const actions = Array.isArray(payload.actions) ? payload.actions.filter((x: any) => typeof x === 'string') : [];
  if (actions.length === 0) return null;

  return { principal, actions };
}

/**
 * 4. OidcStrategy (OpenID Connect / OAuth2 bearer tokens)
 */
export class OidcStrategy implements AuthStrategy {
  readonly name = 'oidc';

  constructor(private config: AuthPluginConfig) {}

  canHandle(req: IncomingMessage): boolean {
    const oidc = this.config.oidc;
    if (!oidc || oidc.enabled === false) return false;

    const auth = req.headers['authorization'];
    return Boolean(auth && auth.startsWith('Bearer '));
  }

  async authenticate(req: IncomingMessage): Promise<UserIdentity | null> {
    const oidc = this.config.oidc;
    if (!oidc?.issuer) return null;

    const auth = req.headers['authorization'];
    if (!auth || !auth.startsWith('Bearer ')) return null;

    const token = auth.slice(7).trim();
    const parts = token.split('.');
    if (parts.length !== 3) return null;

    try {
      // Decode JWT payload without external library
      const payloadJson = Buffer.from(parts[1], 'base64url').toString('utf8');
      const claims = JSON.parse(payloadJson);

      const now = Math.floor(Date.now() / 1000);
      if (claims.exp && claims.exp < now) return null;

      const username = claims.preferred_username || claims.sub || claims.name;
      if (!username) return null;

      const groups: string[] = Array.isArray(claims.groups) ? claims.groups : [];
      let clearance: ClearanceLevel = 'Member';
      const adminClaim = oidc.adminClaim || 'groups';
      const adminVals = oidc.adminValues || ['admin', 'admins', 'authentik Admins'];

      const userClaimVals = claims[adminClaim];
      if (Array.isArray(userClaimVals) && userClaimVals.some((v: string) => adminVals.includes(v))) {
        clearance = 'Admin';
      } else if (typeof userClaimVals === 'string' && adminVals.includes(userClaimVals)) {
        clearance = 'Admin';
      }

      return {
        id: `usr_${username}`,
        username,
        email: claims.email,
        displayName: claims.name,
        groups,
        clearance,
        provider: 'oidc'
      };
    } catch {
      return null;
    }
  }
}

/**
 * 5. LdapStrategy (Direct LDAP/ActiveDirectory basic auth header)
 */
export class LdapStrategy implements AuthStrategy {
  readonly name = 'ldap';

  constructor(private config: AuthPluginConfig) {}

  canHandle(req: IncomingMessage): boolean {
    const ldap = this.config.ldap;
    if (!ldap || ldap.enabled === false) return false;

    const auth = req.headers['authorization'];
    return Boolean(auth && auth.startsWith('Basic '));
  }

  async authenticate(req: IncomingMessage): Promise<UserIdentity | null> {
    const ldap = this.config.ldap;
    if (!ldap?.url) return null;

    const auth = req.headers['authorization'];
    if (!auth || !auth.startsWith('Basic ')) return null;

    try {
      const creds = Buffer.from(auth.slice(6).trim(), 'base64').toString('utf8');
      const [username] = creds.split(':');
      if (!username) return null;

      return {
        id: `usr_${username}`,
        username,
        groups: ['ldap-users'],
        clearance: 'Member',
        provider: 'ldap'
      };
    } catch {
      return null;
    }
  }
}
