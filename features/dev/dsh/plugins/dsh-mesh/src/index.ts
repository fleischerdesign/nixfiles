import { Service, type Context } from '@deepseek-ai/cordis';
import { defineTool } from '@deepseek-ai/dsh-tools';
import * as http from 'node:http';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { spawn } from 'node:child_process';
import { MeshTransportClient } from './protocol.js';
import {
  computeCanonicalWorkspaceUrn,
  getWorkspaceGitFingerprint,
  resolveWorkspacePath,
  extractCwdFromSessionDir,
  syncWorkspaceLocally
} from './workspace.js';
import type {
  MeshPluginConfig,
  PeerScope,
  PeerStatus,
  PeerEndpoint,
  HeartbeatPayload,
  SyncDeltaRequest,
  SyncDeltaResponse,
  RemoteSessionInfo,
  LeaseRecord,
  LeaseHandoffRequest,
  LeaseHandoffResponse,
  LiveStreamChunk
} from './types.js';

export const name = 'mesh';
export const inject = ['tools', 'systemPrompt', 'auth'];

declare module '@deepseek-ai/cordis' {
  interface Context {
    mesh: MeshCoordinatorService;
    webServer?: any;
    auth?: any;
  }
}

export class MeshCoordinatorService extends Service {
  private peers = new Map<string, PeerStatus>();
  private leases = new Map<string, LeaseRecord>();
  private client: MeshTransportClient;
  private server?: http.Server;
  private heartbeatTimer?: NodeJS.Timeout;
  private peersFilePath?: string;

  constructor(ctx: Context, private config: MeshPluginConfig) {
    super(ctx, 'mesh');
    this.client = new MeshTransportClient(5000);

    // 1. Ingest declarative Nix peers (immutable, system, group or user scoped)
    for (const peer of config.peers || []) {
      this.peers.set(peer.id, {
        id: peer.id,
        endpoint: peer.endpoint,
        lastHeartbeatMs: 0,
        rttMs: -1,
        healthy: false,
        maxTxSeen: 0,
        scope: peer.scope || 'system',
        owner: peer.owner,
        group: peer.group,
        dynamic: peer.dynamic || false
      });
    }

    // 2. Ingest persistent dynamic user peers from ~/.dsh/mesh/peers.json
    this.peersFilePath = config.userPeersFile || `${process.env.DSH_HOME || process.env.HOME + '/.dsh'}/mesh/user-peers.json`;
    this.loadDynamicPeers();

    if (config.listenPort) {
      this.startServer(config.listenPort, config.listenHost || '0.0.0.0');
    }

    this.startHeartbeatLoop(config.heartbeatIntervalMs || 10000);

    // 3. Register SIGUSR1 hook for instant lease release upon OS suspend (powerManagement.powerDownCommands)
    process.on('SIGUSR1', () => {
      this.releaseAllLocalLeases();
    });
  }

  /**
   * Release all leases held by this node upon OS suspend or shutdown.
   */
  releaseAllLocalLeases(): void {
    for (const [sessionId, lease] of this.leases.entries()) {
      if (lease.holderNodeId === this.config.nodeId) {
        this.leases.delete(sessionId);
      }
    }
  }

  private loadDynamicPeers(): void {
    if (!this.peersFilePath || !fs.existsSync(this.peersFilePath)) return;
    try {
      const data = JSON.parse(fs.readFileSync(this.peersFilePath, 'utf8'));
      if (Array.isArray(data)) {
        for (const p of data) {
          if (p.id && p.endpoint) {
            this.peers.set(p.id, {
              id: p.id,
              endpoint: p.endpoint,
              lastHeartbeatMs: 0,
              rttMs: -1,
              healthy: false,
              maxTxSeen: 0,
              scope: p.scope || 'user',
              owner: p.owner,
              group: p.group,
              dynamic: true
            });
          }
        }
      }
    } catch {
      // Failed to parse dynamic peers file; ignore
    }
  }

  private saveDynamicPeers(): void {
    if (!this.peersFilePath) return;
    try {
      const dir = path.dirname(this.peersFilePath);
      if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir, { recursive: true });
      }
      const dynamicList = Array.from(this.peers.values())
        .filter(p => p.dynamic)
        .map(p => ({
          id: p.id,
          endpoint: p.endpoint,
          scope: p.scope,
          owner: p.owner,
          group: p.group,
        }));
      fs.writeFileSync(this.peersFilePath, JSON.stringify(dynamicList, null, 2), 'utf8');
    } catch {
      // Failed to save dynamic peers
    }
  }

  getPeer(peerId: string): PeerStatus | undefined {
    return this.peers.get(peerId);
  }

  /**
   * Return peers visible to the requesting tenant.
   * - Admin: sees all system peers, all group peers, and all user peers.
   * - User/Member: sees all system peers + their own personal peers + nodes matching any of their groups.
   */
  getPeers(tenantUsername?: string, clearance?: string, tenantGroups?: string[]): PeerStatus[] {
    const all = Array.from(this.peers.values());
    if (!tenantUsername || clearance === 'Admin') {
      return all;
    }
    return all.filter(p => {
      if (p.scope === 'system') return true;
      if (p.scope === 'user') return p.owner === tenantUsername;
      if (p.scope === 'group' && p.group) {
        return tenantGroups?.includes(p.group) ?? false;
      }
      return false;
    });
  }

  /**
   * Probe endpoint health and latency.
   */
  async probeEndpoint(endpoint: string): Promise<{ healthy: boolean; rttMs: number; error?: string }> {
    try {
      const { rttMs } = await this.client.sendHeartbeat(endpoint, {
        nodeId: this.config.nodeId,
        timestamp: Date.now(),
        maxTx: Date.now()
      });
      return { healthy: true, rttMs };
    } catch (e: any) {
      return { healthy: false, rttMs: -1, error: e.message || String(e) };
    }
  }

  /**
   * Register a new dynamic peer (user or group scoped).
   */
  async addPeer(endpoint: PeerEndpoint, tenant?: { username: string; clearance?: string; groups?: string[] }): Promise<PeerStatus> {
    if (this.peers.has(endpoint.id)) {
      const existing = this.peers.get(endpoint.id)!;
      if (!existing.dynamic) {
        throw new Error(`Cannot overwrite node "${endpoint.id}" (declaratively managed by Nix).`);
      }
    }

    const scope: PeerScope = endpoint.scope || 'user';

    if (scope === 'group') {
      if (!endpoint.group) {
        throw new Error('Group-scoped node requires a group name');
      }
      if (tenant?.clearance !== 'Admin' && (!tenant?.groups || !tenant.groups.includes(endpoint.group))) {
        throw new Error(`Unauthorized: You are not a member of group "${endpoint.group}".`);
      }
    }

    // SSRF & loopback protection: prevent targeting sensitive system ports
    const url = endpoint.endpoint.startsWith('http') ? endpoint.endpoint : `http://${endpoint.endpoint}`;
    try {
      const parsedUrl = new URL(url);
      const port = Number(parsedUrl.port) || 80;
      if (['127.0.0.1', 'localhost', '::1'].includes(parsedUrl.hostname) && [22, 5432, 6379, 9090].includes(port)) {
        throw new Error(`Prohibited target port ${port} on loopback.`);
      }
    } catch (e: any) {
      if (e.message.includes('Prohibited target port')) throw e;
    }

    const probe = await this.probeEndpoint(endpoint.endpoint);

    const peerStatus: PeerStatus = {
      id: endpoint.id,
      endpoint: endpoint.endpoint,
      lastHeartbeatMs: probe.healthy ? Date.now() : 0,
      rttMs: probe.rttMs,
      healthy: probe.healthy,
      maxTxSeen: 0,
      scope,
      owner: scope === 'user' ? tenant?.username : undefined,
      group: scope === 'group' ? endpoint.group : undefined,
      dynamic: true
    };

    this.peers.set(endpoint.id, peerStatus);
    this.saveDynamicPeers();
    return peerStatus;
  }

  /**
   * Remove a dynamic peer. Declarative Nix peers cannot be deleted.
   */
  removePeer(peerId: string, tenant?: { username: string; clearance?: string; groups?: string[] }): boolean {
    const peer = this.peers.get(peerId);
    if (!peer) return false;

    if (!peer.dynamic) {
      throw new Error(`Node "${peerId}" is declaratively configured by Nix and cannot be removed at runtime.`);
    }

    if (tenant?.clearance !== 'Admin') {
      if (peer.scope === 'user' && peer.owner && peer.owner !== tenant?.username) {
        throw new Error(`Unauthorized: You do not own personal node "${peerId}".`);
      }
      if (peer.scope === 'group' && peer.group && (!tenant?.groups || !tenant.groups.includes(peer.group))) {
        throw new Error(`Unauthorized: You are not a member of group "${peer.group}" for node "${peerId}".`);
      }
    }

    this.peers.delete(peerId);
    this.saveDynamicPeers();
    return true;
  }

  async dispatchTask(peerId: string, toolName: string, args: Record<string, any>, tenant?: any): Promise<any> {
    const peer = this.peers.get(peerId);
    if (!peer) {
      throw new Error(`Target peer node "${peerId}" not found in mesh registry.`);
    }

    // Security check: If target peer is personal to another user, deny dispatch
    if (peer.scope === 'user' && peer.owner && tenant?.username && peer.owner !== tenant.username && tenant?.clearance !== 'Admin') {
      throw new Error(`PermissionDenied: Personal node "${peerId}" belongs to user "${peer.owner}".`);
    }

    // Security check: If target peer is group-scoped, caller must be member of that group
    if (peer.scope === 'group' && peer.group && tenant?.clearance !== 'Admin') {
      if (!tenant?.groups || !tenant.groups.includes(peer.group)) {
        throw new Error(`PermissionDenied: Node "${peerId}" is restricted to group "${peer.group}".`);
      }
    }

    const taskId = `tx-${Date.now()}-${Math.random().toString(36).substring(2, 7)}`;
    return this.client.executeRemoteTask(peer.endpoint, {
      fromNodeId: this.config.nodeId,
      taskId,
      toolName,
      arguments: args,
      timestamp: Date.now(),
      capability: {
        taskId,
        issuedFor: `user:${tenant?.username || 'anonymous'}`,
        authorizedGroup: peer.group ? `group:${peer.group}` : undefined,
        expiresAt: Date.now() + 120000
      }
    });
  }

  /**
   * Scans local DSH session persistence store for active and archived sessions.
   */
  getLocalSessions(): RemoteSessionInfo[] {
    const sessions: RemoteSessionInfo[] = [];
    const dshHome = process.env.DSH_HOME || path.join(process.env.HOME || '/root', '.dsh');
    const sessionsDir = path.join(dshHome, 'sessions');

    if (!fs.existsSync(sessionsDir)) return sessions;

    try {
      const workspaceDirs = fs.readdirSync(sessionsDir);
      for (const wsDir of workspaceDirs) {
        const wsPath = path.join(sessionsDir, wsDir);
        if (!fs.statSync(wsPath).isDirectory()) continue;

        const sessionDirs = fs.readdirSync(wsPath);
        for (const sDir of sessionDirs) {
          if (!sDir.startsWith('session-')) continue;
          const sPath = path.join(wsPath, sDir);
          if (!fs.statSync(sPath).isDirectory()) continue;

          const sessionId = sDir.replace('session-', '');
          const lockFile = path.join(sPath, 'session.lock');
          const hasLock = fs.existsSync(lockFile);

          const lease = this.leases.get(sessionId);
          const leaseActive = lease ? lease.expiresAt > Date.now() && lease.holderNodeId === this.config.nodeId : hasLock;

          // 1. First attempt to extract authoritative execution cwd directly from session file header
          const sessionCwd = extractCwdFromSessionDir(sPath);
          // 2. Fall back to smart filesystem-aware directory resolution
          const realWsPath = sessionCwd && fs.existsSync(sessionCwd)
            ? sessionCwd
            : resolveWorkspacePath(wsDir, sessionsDir);

          const canonical = computeCanonicalWorkspaceUrn(realWsPath);
          const gitFp = getWorkspaceGitFingerprint(realWsPath);

          sessions.push({
            sessionId,
            workspaceUrn: canonical.urn,
            workspaceLabel: canonical.label,
            workspaceType: canonical.type,
            nodeId: this.config.nodeId,
            lastTurnSeq: 0,
            updatedAt: fs.statSync(sPath).mtimeMs,
            leaseEpoch: lease?.leaseEpoch || 1,
            leaseHolder: lease?.holderNodeId || (hasLock ? this.config.nodeId : 'none'),
            isLeaseActive: leaseActive,
            gitFingerprint: gitFp
          });
        }
      }
    } catch {
      // Ignore directory scan errors
    }

    return sessions;
  }

  /**
   * Distributed Lease Token acquisition.
   */
  acquireLease(sessionId: string, requestingNodeId: string, epoch: number, force = false): LeaseHandoffResponse {
    const existing = this.leases.get(sessionId);
    const now = Date.now();

    if (existing && existing.expiresAt > now && existing.holderNodeId !== requestingNodeId && !force) {
      return {
        sessionId,
        success: false,
        grantedEpoch: existing.leaseEpoch,
        holderNodeId: existing.holderNodeId,
        lastSeq: 0,
        error: `Session "${sessionId}" is actively leased to node "${existing.holderNodeId}".`
      };
    }

    const nextEpoch = Math.max((existing?.leaseEpoch || 0) + 1, epoch);
    const lease: LeaseRecord = {
      sessionId,
      holderNodeId: requestingNodeId,
      leaseEpoch: nextEpoch,
      expiresAt: now + (this.config.leaseTtlMs || 30000),
      grantedAt: now
    };

    this.leases.set(sessionId, lease);

    return {
      sessionId,
      success: true,
      grantedEpoch: nextEpoch,
      holderNodeId: requestingNodeId,
      lastSeq: 0
    };
  }

  /**
   * Release lease upon suspend or user handoff.
   */
  releaseLease(sessionId: string, holderNodeId: string): boolean {
    const existing = this.leases.get(sessionId);
    if (!existing || existing.holderNodeId !== holderNodeId) return false;
    this.leases.delete(sessionId);
    return true;
  }

  private startServer(port: number, host: string): void {
    this.server = http.createServer((req, res) => {
      // Support GET /mesh/sessions and GET /mesh/workspace/archive
      if (req.method === 'GET') {
        const parsedUrl = new URL(req.url || '/', `http://${req.headers.host || 'localhost'}`);
        if (parsedUrl.pathname === '/mesh/sessions') {
          try {
            const sessions = this.getLocalSessions();
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify(sessions));
          } catch (e: any) {
            res.writeHead(500, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ error: e.message || String(e) }));
          }
          return;
        }

        if (parsedUrl.pathname === '/mesh/workspace/archive') {
          const relPath = parsedUrl.searchParams.get('path');
          if (!relPath) {
            res.writeHead(400, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ error: 'Missing path query parameter' }));
            return;
          }

          const home = process.env.HOME || '/root';
          const absPath = path.resolve(home, relPath);

          // Prevent path traversal outside home
          if (!absPath.startsWith(home) || !fs.existsSync(absPath) || !fs.statSync(absPath).isDirectory()) {
            res.writeHead(404, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ error: 'Directory not found or access forbidden' }));
            return;
          }

          // Stream directory 1:1 via tar | zstd -3 into HTTP response
          res.writeHead(200, {
            'Content-Type': 'application/x-zstd-tar',
            'Transfer-Encoding': 'chunked'
          });

          const tar = spawn('tar', ['-C', absPath, '-cf', '-', '.']);
          const zstd = spawn('zstd', ['-3', '-c']);

          tar.stdout.pipe(zstd.stdin);
          zstd.stdout.pipe(res);

          req.on('close', () => {
            tar.kill();
            zstd.kill();
          });
          return;
        }
      }

      if (req.method !== 'POST') {
        res.writeHead(405);
        res.end();
        return;
      }

      let body = '';
      req.on('data', (d) => { body += d; });
      req.on('end', () => {
        try {
          const parsed = JSON.parse(body || '{}');

          if (req.url === '/mesh/heartbeat') {
            const resp: HeartbeatPayload = {
              nodeId: this.config.nodeId,
              timestamp: Date.now(),
              maxTx: Date.now(),
              presence: this.localPresence()
            };
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify(resp));
          } else if (req.url === '/mesh/lease/handoff') {
            // Direct P2P Lease Token handoff
            const handoffReq = parsed as LeaseHandoffRequest;
            const resp = this.acquireLease(
              handoffReq.sessionId,
              handoffReq.requestingNodeId,
              handoffReq.currentEpoch,
              handoffReq.force
            );
            res.writeHead(resp.success ? 200 : 409, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify(resp));
          } else if (req.url === '/mesh/stream/chunk') {
            // Ingest live streamed token chunk or tool event from peer
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ acknowledged: true }));
          } else if (req.url === '/mesh/sync') {
            // Delta response for CvRDT merge
            const resp: SyncDeltaResponse = {
              fromNodeId: this.config.nodeId,
              facts: [],
              maxTx: Date.now()
            };
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify(resp));
          } else if (req.url === '/mesh/task') {
            // Remote tool execution request under MTAA Task Contract
            void (async () => {
              try {
                const taskReq = parsed;
                const toolName = taskReq.toolName;
                const toolArgs = taskReq.arguments || {};

                // Execute tool via Cordis tools service
                if (this.ctx.tools) {
                  const out = await this.ctx.tools.execute({
                    callId: `remote-${taskReq.taskId}` as any,
                    name: toolName,
                    arguments: toolArgs,
                    signal: new AbortController().signal
                  });

                  res.writeHead(200, { 'Content-Type': 'application/json' });
                  res.end(JSON.stringify({
                    fromNodeId: this.config.nodeId,
                    taskId: taskReq.taskId,
                    success: !out.isError,
                    result: out.value || out.content,
                    error: out.error?.message,
                    executedAt: Date.now()
                  }));
                } else {
                  res.writeHead(503, { 'Content-Type': 'application/json' });
                  res.end(JSON.stringify({ error: 'Tools service unavailable on target node' }));
                }
              } catch (e: any) {
                res.writeHead(500, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ error: e.message || String(e) }));
              }
            })();
          } else {
            res.writeHead(404);
            res.end();
          }
        } catch {
          res.writeHead(400);
          res.end();
        }
      });
    });

    this.server.listen(port, host);
  }

  private startHeartbeatLoop(intervalMs: number): void {
    this.heartbeatTimer = setInterval(() => {
      this.pollPeers();
    }, intervalMs);
  }

  private async pollPeers(): Promise<void> {
    for (const [id, peer] of this.peers.entries()) {
      try {
        const { rttMs, response } = await this.client.sendHeartbeat(peer.endpoint, {
          nodeId: this.config.nodeId,
          timestamp: Date.now(),
          maxTx: Date.now(),
          presence: this.localPresence()
        });

        peer.lastHeartbeatMs = Date.now();
        peer.rttMs = rttMs;
        peer.healthy = true;
        peer.maxTxSeen = response.maxTx;
        // Store the peer's advertised presence (tenant/group-level), if any.
        if (response && Array.isArray(response.presence?.tenants)) {
          peer.presence = {
            tenants: response.presence.tenants,
            groups: Array.isArray(response.presence.groups) ? response.presence.groups : [],
            updatedAt: Date.now(),
          };
        }
      } catch {
        peer.healthy = false;
        peer.rttMs = -1;
      }
    }
  }

  /** Local presence (hosted tenants/groups) from the dsh-auth PresenceRegistry. */
  private localPresence(): { tenants: string[]; groups: string[] } {
    try {
      const auth = this.ctx.get('auth') as any;
      const reg = auth?.presence;
      if (reg && typeof reg.tenants === 'function' && typeof reg.groups === 'function') {
        const tenants = (reg.tenants() as any[]).map((t) => t.username || t.tenantId);
        const groups = (reg.groups() as string[]) || [];
        return { tenants: tenants.map(String), groups: groups.map(String) };
      }
    } catch {
      // presence provider unavailable -> advertise empty
    }
    return { tenants: [], groups: [] };
  }

  close(): void {
    if (this.heartbeatTimer) clearInterval(this.heartbeatTimer);
    this.server?.close();
  }

  /**
   * Aggregate local sessions and all remote sessions from healthy mesh peers.
   */
  async getAllMeshSessions(): Promise<RemoteSessionInfo[]> {
    const local = this.getLocalSessions();
    const results: RemoteSessionInfo[] = [...local];

    for (const peer of this.peers.values()) {
      if (!peer.healthy) continue;
      try {
        const remote = await this.client.listRemoteSessions(peer.endpoint);
        if (Array.isArray(remote)) {
          results.push(...remote);
        }
      } catch {
        // Skip unreachable peer
      }
    }

    return results;
  }
}

export function apply(ctx: Context, config: MeshPluginConfig): void {
  const service = new MeshCoordinatorService(ctx, config || { nodeId: 'standalone' });
  ctx.mesh = service;

  ctx.effect(() => {
    return () => {
      service.close();
    };
  });

  // Register HTTP routes for cluster web UI when webServer is available
  ctx.inject(['webServer'], (wsCtx: any) => {
    wsCtx.webServer.register({
      kind: 'exact',
      path: '/api/mesh/peers',
      handler: async (req: any, res: any) => {
        const tenant = (req as any).tenant || { username: 'local', clearance: 'Admin', groups: ['wheel'] };

        if (req.method === 'GET') {
          try {
            res.statusCode = 200;
            res.setHeader('Content-Type', 'application/json');
            res.end(JSON.stringify({
              nodeId: config?.nodeId || 'standalone',
              peers: service.getPeers(tenant.username, tenant.clearance, tenant.groups)
            }));
          } catch (err: any) {
            res.statusCode = 500;
            res.setHeader('Content-Type', 'application/json');
            res.end(JSON.stringify({ error: err.message }));
          }
          return;
        }

        if (req.method === 'POST') {
          let body = '';
          req.on('data', (chunk: any) => { body += chunk; });
          req.on('end', async () => {
            try {
              const payload = JSON.parse(body);
              if (!payload.id || !payload.endpoint) {
                res.statusCode = 400;
                res.end(JSON.stringify({ error: 'Missing required id or endpoint field' }));
                return;
              }

              const scope: PeerScope = payload.scope === 'group' ? 'group' : 'user';

              const peer = await service.addPeer({
                id: String(payload.id).trim(),
                endpoint: String(payload.endpoint).trim(),
                tags: payload.tags || [scope === 'group' ? 'group' : 'personal'],
                scope,
                group: scope === 'group' ? String(payload.group || '').trim() : undefined,
                owner: scope === 'user' ? tenant.username : undefined,
                dynamic: true
              }, tenant);

              res.statusCode = 201;
              res.setHeader('Content-Type', 'application/json');
              res.end(JSON.stringify({ peer }));
            } catch (err: any) {
              res.statusCode = err.message.includes('managed by Nix') ? 409 : (err.message.includes('Unauthorized') ? 403 : 400);
              res.setHeader('Content-Type', 'application/json');
              res.end(JSON.stringify({ error: err.message }));
            }
          });
          return;
        }

        if (req.method === 'DELETE') {
          const parsedUrl = new URL(`http://${req.headers.host || 'localhost'}${req.url}`);
          const peerId = parsedUrl.searchParams.get('id');
          if (!peerId) {
            res.statusCode = 400;
            res.end(JSON.stringify({ error: 'Missing id query parameter' }));
            return;
          }

          try {
            service.removePeer(peerId, tenant);
            res.statusCode = 200;
            res.setHeader('Content-Type', 'application/json');
            res.end(JSON.stringify({ success: true, removed: peerId }));
          } catch (err: any) {
            res.statusCode = err.message.includes('Unauthorized') ? 403 : 400;
            res.setHeader('Content-Type', 'application/json');
            res.end(JSON.stringify({ error: err.message }));
          }
          return;
        }

        res.statusCode = 405;
        res.end(JSON.stringify({ error: 'Method Not Allowed' }));
      }
    });

    wsCtx.webServer.register({
      kind: 'exact',
      path: '/api/mesh/sessions',
      handler: async (req: any, res: any) => {
        if (req.method === 'GET') {
          try {
            const allSessions = await service.getAllMeshSessions();
            res.statusCode = 200;
            res.setHeader('Content-Type', 'application/json');
            res.end(JSON.stringify({
              nodeId: config?.nodeId || 'standalone',
              sessions: allSessions
            }));
          } catch (err: any) {
            res.statusCode = 500;
            res.setHeader('Content-Type', 'application/json');
            res.end(JSON.stringify({ error: err.message }));
          }
          return;
        }

        res.statusCode = 405;
        res.end(JSON.stringify({ error: 'Method Not Allowed' }));
      }
    });

    wsCtx.webServer.register({
      kind: 'exact',
      path: '/api/mesh/workspace/sync',
      handler: async (req: any, res: any) => {
        if (req.method === 'POST') {
          let body = '';
          req.on('data', (chunk: any) => { body += chunk; });
          req.on('end', () => {
            try {
              const payload = JSON.parse(body || '{}');
              const { workspaceUrn, preferredDir, peerNode } = payload;
              if (!workspaceUrn) {
                res.statusCode = 400;
                res.setHeader('Content-Type', 'application/json');
                res.end(JSON.stringify({ error: 'Missing workspaceUrn in request body' }));
                return;
              }

              // Resolve peer endpoint if peerNode was provided
              let peerEndpoint = payload.peerEndpoint;
              if (!peerEndpoint && peerNode) {
                const p = service.getPeer(peerNode);
                if (p) peerEndpoint = p.endpoint;
              }

              const result = syncWorkspaceLocally(workspaceUrn, preferredDir, peerEndpoint);
              res.statusCode = result.success ? 200 : 422;
              res.setHeader('Content-Type', 'application/json');
              res.end(JSON.stringify(result));
            } catch (err: any) {
              res.statusCode = 500;
              res.setHeader('Content-Type', 'application/json');
              res.end(JSON.stringify({ error: err.message }));
            }
          });
          return;
        }

        res.statusCode = 405;
        res.end(JSON.stringify({ error: 'Method Not Allowed' }));
      }
    });
  });

  ctx.systemPrompt.section({
    name: 'tool:mesh',
    order: 270,
    text: 'Use mesh_peers to inspect cluster health, roundtrip latencies, and distributed synchronization across peer nodes.'
  });

  ctx.tools.register(
    defineTool({
      name: 'mesh_peers',
      description: 'List connected cluster peer nodes, health status, and roundtrip latencies.',
      parameters: {},
      output: {
        schema: {
          type: 'object',
          additionalProperties: true,
          properties: {
            nodeId: { type: 'string' },
            peers: { type: 'array' }
          }
        },
        render: (_args, value: any) => [
          {
            type: 'text',
            text: `<mesh_status local_node="${value.nodeId}">\n${JSON.stringify(value.peers, null, 2)}\n</mesh_status>`
          }
        ]
      },
      async execute(): Promise<any> {
        const authService = ctx.get('auth');
        const tenant = authService?.activeTenant;
        const peers = service.getPeers(tenant?.username, tenant?.clearance, tenant?.groups);
        // Ensure lossless JSON by eliminating any undefined properties (which fail snapshotJsonValue)
        const sanitizedPeers = JSON.parse(JSON.stringify(peers));

        return {
          nodeId: config.nodeId || 'unknown',
          peers: sanitizedPeers
        };
      }
    })
  );

  // Tool: Remote Task Dispatching under MTAA Contract
  ctx.tools.register(
    defineTool({
      name: 'mesh_dispatch',
      description: 'Dispatch an atomic tool call to be executed on a remote peer node in the cluster mesh.',
      parameters: {
        peer_id: { type: 'string', required: true, description: 'Hostname / ID of target peer node (e.g. mackaye, rollins, strummer).' },
        tool_name: { type: 'string', required: true, description: 'Target tool to invoke remotely.' },
        arguments: { type: 'object', additionalProperties: true, description: 'Arguments payload for the remote tool.' }
      },
      output: {
        schema: {
          type: 'object',
          additionalProperties: true,
          properties: {
            fromNodeId: { type: 'string' },
            taskId: { type: 'string' },
            success: { type: 'boolean' }
          }
        },
        render: (_args, value: any) => [
          {
            type: 'text',
            text: `<mesh_dispatch peer="${value.fromNodeId}" task="${value.taskId}" success="${value.success}">\n${JSON.stringify(value.result || value.error, null, 2)}\n</mesh_dispatch>`
          }
        ]
      },
      async execute(args: any): Promise<any> {
        const authService = ctx.get('auth');
        const tenant = authService?.activeTenant;
        const res = await service.dispatchTask(args.peer_id, args.tool_name, args.arguments || {}, tenant);
        return JSON.parse(JSON.stringify(res));
      }
    })
  );

  // Tool: Cluster-wide Session Discovery
  ctx.tools.register(
    defineTool({
      name: 'mesh_sessions',
      description: 'Discover active and archived agent sessions across all connected peer nodes in the cluster.',
      parameters: {},
      output: {
        schema: {
          type: 'object',
          additionalProperties: true,
          properties: {
            nodeId: { type: 'string' },
            sessions: { type: 'array' }
          }
        },
        render: (_args, value: any) => [
          {
            type: 'text',
            text: `<mesh_sessions local_node="${value.nodeId}">\n${JSON.stringify(value.sessions, null, 2)}\n</mesh_sessions>`
          }
        ]
      },
      async execute(): Promise<any> {
        const all = await service.getAllMeshSessions();
        return {
          nodeId: config.nodeId || 'unknown',
          sessions: JSON.parse(JSON.stringify(all))
        };
      }
    })
  );
}
