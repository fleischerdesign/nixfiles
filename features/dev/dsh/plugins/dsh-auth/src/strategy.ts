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

    // Verify HMAC-SHA256 signature
    const method = req.method || 'GET';
    const url = req.url || '/';
    const payload = `${method}:${url}:${timestampStr}:${node}`;
    const expectedSig = crypto.createHmac('sha256', pm.clusterSecret).update(payload).digest('hex');

    const expectedBuf = Buffer.from(expectedSig);
    const actualBuf = Buffer.from(signature);
    if (expectedBuf.length !== actualBuf.length || !crypto.timingSafeEqual(expectedBuf, actualBuf)) {
      return null;
    }

    return {
      id: `node_${node}`,
      username: `node:${node}`,
      groups: ['mesh-nodes'],
      clearance: 'Admin', // Peer nodes run with Admin capability under Task Contract constraints
      provider: 'peer-mesh'
    };
  }
}
