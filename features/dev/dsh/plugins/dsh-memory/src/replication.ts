/**
 * @module dsh-memory/replication
 * Cross-Node memory replication (C7). Immutable versions merge as a CvRDT
 * union (G-Set) and logical retracts as an OR-Set tombstone stream; both are
 * causally ordered by a Hybrid Logical Clock (HLC), so convergence is
 * order-independent and clock-skew robust. Authorization uses capability
 * tokens (see ./capability.js) with tenant + scope caveats.
 */
import * as http from 'node:http';
import * as crypto from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
import { HLC } from './hlc.js';
import { createToken, decodeToken, encodeToken, type CapClaims, type CapabilityToken } from './capability.js';

export interface ReplicationPeer {
  nodeId: string;
  endpoint: string; // "host:port" or URL
  direction?: 'pull' | 'push' | 'bidirectional';
  scopes?: string[];
}

export interface MemoryReplicationConfig {
  enabled?: boolean;
  nodeId?: string;
  tenantContext?: string; // "user:<u>" | "group:<g>"
  secretEnv?: string;
  peers?: ReplicationPeer[];
  listenPort?: number;
  listenHost?: string;
  syncIntervalMs?: number;
  maxVersionsPerSync?: number;
}

/** A fully serialised fact version (mirrors `facts` columns + HLC). */
export interface ReplicatedVersion {
  id: string;
  subject: string;
  predicate: string;
  object: string;
  valid_from: number;
  valid_to: number;
  tx_from: number;
  tx_counter: number;
  tx_node: string;
  tx_to: number;
  type_constraint: string;
  confidence: number;
  security_label: string;
  status: string;
  scope_type: string;
  scope_id: string;
  author: string;
  epistemic_class: string;
  fts_tokens: string;
  embedding_blob: string | null; // base64
}

export interface ReplicatedTombstone {
  id: string;
  subject: string;
  predicate: string;
  scope_type: string;
  scope_id: string;
  tx_from: number;
  tx_counter: number;
  tx_node: string;
  origin: string;
}

export interface HlcCursor {
  phys: number;
  counter: number;
  node: string;
}

export interface SyncDeltaRequest {
  fromNodeId: string;
  since: HlcCursor;
  scopes: string[];
  max: number;
}

export interface SyncDeltaResponse {
  fromNodeId: string;
  versions: ReplicatedVersion[];
  tombstones: ReplicatedTombstone[];
  nextCursor: HlcCursor;
  complete: boolean;
}

function hmac(secret: string, body: string): string {
  return crypto.createHmac('sha256', secret).update(body).digest('hex');
}

function timingSafeEqual(a: string, b: string): boolean {
  const ba = Buffer.from(a);
  const bb = Buffer.from(b);
  return ba.length === bb.length && crypto.timingSafeEqual(ba, bb);
}

/** Scope visibility for *serving*: only explicitly-listed scopes replicate. */
export function canReplicateScope(scopeType: string, scopeId: string, allowed: string[]): boolean {
  const id = scopeType === 'public' ? 'public' : `${scopeType}:${scopeId.replace(/^[a-z]+:/, '')}`;
  return allowed.includes(id);
}

/** A peer's advertised presence: which tenants/groups it hosts (agnostic). */
export interface PeerPresence {
  nodeId: string;
  tenants: string[]; // usernames with an authenticated presence on that node
  groups: string[];  // e.g. ['group:dev', 'group:family']
  updatedAt: number;
}

/**
 * Agnostic scope→peer derivation (docs/dsh/08): given the scopes this node
 * *wants* to replicate, a peer's presence, and the LOCAL subject, return the
 * subset that should actually sync to that peer.
 *   - `public`      -> always (opt-in by `wantScopes`)
 *   - `group:<g>`   -> only if the peer hosts group `g`
 *   - `user:<u>`    -> only if `u` is the LOCAL subject (privacy: a node never
 *                      pulls another user's private facts just because the peer
 *                      hosts them; the serve-side canSee re-enforces this too)
 *   - `repo:*`      -> never (node-bound, I-SEC3)
 */
export function deriveScopes(wantScopes: string[], peer: PeerPresence | null | undefined, localUser: string): string[] {
  const out = new Set<string>();
  for (const s of wantScopes || []) {
    if (s === 'public') { out.add('public'); continue; }
    if (s.startsWith('group:')) {
      if (peer && peer.groups.includes(s)) out.add(s);
    } else if (s.startsWith('user:')) {
      const u = s.slice('user:'.length);
      if (u === localUser) out.add(s);
    }
    // repo:* and unknown scopes are intentionally not derived (never replicate).
  }
  return Array.from(out);
}

function cursorTuple(c: HlcCursor): [number, number, string] {
  return [c.phys, c.counter, c.node];
}

export class MemoryReplicator {
  private readonly secret: string;
  private readonly nodeId: string;
  private readonly tenantContext: string;
  private readonly peerNodes: ReplicationPeer[];
  private readonly maxVersions: number;
  private readonly db: DatabaseSync;
  private readonly wantScopes: string[];
  private readonly getPresence: () => PeerPresence;
  private server?: http.Server;
  private timer?: NodeJS.Timeout;

  constructor(
    opts: {
      db: DatabaseSync;
      secret: string;
      nodeId: string;
      tenantContext: string;
      peers?: ReplicationPeer[];
      syncIntervalMs?: number;
      maxVersionsPerSync?: number;
      wantScopes?: string[];
      getPresence?: () => PeerPresence;
    },
  ) {
    this.db = opts.db;
    this.secret = opts.secret;
    this.nodeId = opts.nodeId;
    this.tenantContext = opts.tenantContext || 'user:local';
    this.peerNodes = (opts.peers || []).filter((p) => p.nodeId !== this.nodeId);
    this.maxVersions = opts.maxVersionsPerSync ?? 512;
    this.wantScopes = opts.wantScopes || ['public'];
    this.getPresence = opts.getPresence || (() => ({ nodeId: this.nodeId, tenants: [], groups: [], updatedAt: Date.now() }));
    this.ensureSyncTables();
  }

  private myPresence(): PeerPresence {
    return this.getPresence();
  }

  private ensureSyncTables(): void {
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS memory_sync_cursor (
        peer_key TEXT PRIMARY KEY,
        cur_phys INTEGER NOT NULL DEFAULT 0,
        cur_counter INTEGER NOT NULL DEFAULT 0,
        cur_node TEXT NOT NULL DEFAULT ''
      );
      CREATE TABLE IF NOT EXISTS memory_sync_nonce (
        nonce TEXT PRIMARY KEY,
        exp INTEGER NOT NULL
      );
    `);
  }

  // --- Token helpers --------------------------------------------------------

  /** Token grant for this node talking to `targetPeer` (only the allowed scopes). */
  private makeGrant(targetPeer: ReplicationPeer, since: HlcCursor, scopes: string[]): CapabilityToken {
    return createToken(this.secret, {
      iss: this.nodeId,
      sub: this.tenantContext,
      scopes: (scopes && scopes.length ? scopes : ['public']),
      ops: ['sync'],
      sink: targetPeer.nodeId,
      exp: Date.now() + 120_000,
    });
  }

  /** Fetch a peer's presence (agnostic derivation input). */
  private async fetchPresence(peer: ReplicationPeer): Promise<PeerPresence> {
    const base = peer.endpoint.startsWith('http') ? peer.endpoint : `http://${peer.endpoint}`;
    const url = `${base}/mesh/memory/presence`;
    const token = createToken(this.secret, {
      iss: this.nodeId,
      sub: this.tenantContext,
      scopes: ['public'],
      ops: ['sync'],
      sink: peer.nodeId,
      exp: Date.now() + 120_000,
    });
    const text = await this.get(url, { 'X-DSH-CAP': encodeToken(token) });
    const p = safeParse(text);
    return p && Array.isArray(p.tenants) ? (p as PeerPresence) : { nodeId: peer.nodeId, tenants: [], groups: [], updatedAt: Date.now() };
  }

  // --- Serving (receive a peer's pull request) -----------------------------

  startServer(port: number, host = '0.0.0.0'): void {
    if (this.server) return;
    this.server = http.createServer((req: http.IncomingMessage, res: http.ServerResponse) => {
      // Presence advertisement (agnostic peer derivation). Presence is not
      // sensitive (I-SEC10: only host listing, no facts), but we still require a
      // valid capability so only trusted peers learn it.
      if (req.method === 'GET' && req.url === '/mesh/memory/presence') {
        const capStr = req.headers['x-dsh-cap'] as string | undefined;
        if (!capStr) { this.reject(res, 401, 'missing capability'); return; }
        try {
          const claims = decodeToken(this.secret, capStr);
          if (claims.sink && claims.sink !== this.nodeId) { this.reject(res, 403, 'token not issued to this node'); return; }
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify(this.myPresence()));
        } catch (e: any) {
          this.reject(res, 403, e.message || String(e));
        }
        return;
      }

      if (req.method !== 'POST' || req.url !== '/mesh/memory/sync') {
        res.writeHead(404);
        res.end();
        return;
      }
      let body = '';
      req.on('data', (d) => { body += d; });
      req.on('end', () => {
        try {
          // 1. Capability authorization (tenant + scope caveats, expiry, nonce).
          const capStr = req.headers['x-dsh-cap'] as string | undefined;
          if (!capStr) { this.reject(res, 401, 'missing capability'); return; }
          const claims = decodeToken(this.secret, capStr);
          if (claims.sink && claims.sink !== this.nodeId) { this.reject(res, 403, 'token not issued to this node'); return; }
          if (!claims.ops.includes('sync')) { this.reject(res, 403, 'op not granted'); return; }
          if (this.nonceReplayed(claims.nonce, claims.exp)) { this.reject(res, 401, 'replayed nonce'); return; }

          // 2. Body integrity (HMAC over raw body + freshness window).
          const bodyHmac = req.headers['x-dsh-body-hmac'] as string | undefined;
          if (!bodyHmac || !timingSafeEqual(bodyHmac, hmac(this.secret, body))) {
            this.reject(res, 401, 'bad body signature');
            return;
          }
          const parsed = safeParse(body);
          const ts = parsed?.timestamp as number | undefined;
          if (typeof ts !== 'number' || Math.abs(Date.now() - ts) > 5 * 60 * 1000) {
            this.reject(res, 401, 'stale/future timestamp');
            return;
          }

          const req_: SyncDeltaRequest = {
            fromNodeId: parsed?.fromNodeId || 'unknown',
            since: parsed?.since || { phys: 0, counter: 0, node: '' },
            scopes: Array.isArray(parsed?.scopes) ? (parsed.scopes as string[]) : ['public'],
            max: (parsed?.max as number) || this.maxVersions,
          };
          // Enforce scope caveat: the requested scopes must be a subset of grant.
          if (!req_.scopes.every((s) => claims.scopes.includes(s))) {
            this.reject(res, 403, 'requested scope not in grant');
            return;
          }
          // Multi-tenant user-scope ownership: a `user:<u>` scope may only be
          // served if the requesting tenant owns it (privacy, I-SEC2). Nodes are
          // multi-tenant, so we do NOT require an exact single-tenantContext match.
          if (!req_.scopes.every((s) => !s.startsWith('user:') || s === claims.sub)) {
            this.reject(res, 403, 'user scope not owned by requester');
            return;
          }
          const resp = this.produceDelta(req_);
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify(resp));
        } catch (e: any) {
          this.reject(res, e.message?.includes('Capability') ? 403 : 400, e.message || String(e));
        }
      });
    });
    this.server.listen(port, host);
  }

  private reject(res: http.ServerResponse, code: number, msg: string): void {
    res.writeHead(code, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: msg }));
  }

  private nonceReplayed(nonce: string, exp: number): boolean {
    // Record nonce; if already present and unexpired -> replay.
    const row = this.db.prepare(`SELECT exp FROM memory_sync_nonce WHERE nonce = ?`).get(nonce) as any;
    if (row && row.exp > Date.now()) return true;
    this.db.prepare(`
      INSERT INTO memory_sync_nonce (nonce, exp) VALUES (?, ?)
      ON CONFLICT(nonce) DO UPDATE SET exp = excluded.exp
    `).run(nonce, exp);
    return false;
  }

  private produceDelta(req: SyncDeltaRequest): SyncDeltaResponse {
    const allowed = req.scopes.length ? req.scopes : ['public'];
    const [cp, cc, cn] = cursorTuple(req.since);

    const factRows = this.db.prepare(`
      SELECT id, subject, predicate, object, valid_from, valid_to, tx_from, tx_to, tx_counter, tx_node,
        type_constraint, confidence, security_label, status, scope_type, scope_id,
        author, epistemic_class, fts_tokens, embedding_blob
      FROM facts
      WHERE (tx_from, tx_counter, tx_node) > (?, ?, ?)
      ORDER BY tx_from ASC, tx_counter ASC, tx_node ASC
    `).all(cp, cc, cn) as any[];
    const tombRows = this.db.prepare(`
      SELECT id, subject, predicate, scope_type, scope_id, tx_from, tx_counter, tx_node, origin
      FROM memory_tombstones WHERE tombstone_status = '0'
        AND (tx_from, tx_counter, tx_node) > (?, ?, ?)
    `).all(cp, cc, cn) as any[];

    const versions: ReplicatedVersion[] = [];
    const tombstones: ReplicatedTombstone[] = [];
    // Merge-sort facts + tombstones by HLC, paginate, and compute nextCursor as
    // the last HLC we *scan* (so filtered versions are never re-served).
    const merged: Array<{ hlc: HLC; kind: 'fact' | 'tomb'; row: any }> = [
      ...factRows.map((r) => ({ hlc: new HLC(r.tx_from, r.tx_counter, r.tx_node), kind: 'fact' as const, row: r })),
      ...tombRows.map((r) => ({ hlc: new HLC(r.tx_from, r.tx_counter, r.tx_node), kind: 'tomb' as const, row: r })),
    ].sort((a, b) => HLC.compare(a.hlc, b.hlc));

    let scanned = 0;
    let lastHlc = new HLC(req.since.phys, req.since.counter, req.since.node);
    for (const it of merged) {
      lastHlc = it.hlc;
      scanned++;
      if (scanned > req.max) break;
      if (!canReplicateScope(it.row.scope_type, it.row.scope_id, allowed)) continue;
      if (it.kind === 'fact') {
        versions.push({
          id: it.row.id, subject: it.row.subject, predicate: it.row.predicate, object: it.row.object,
          valid_from: it.row.valid_from, valid_to: it.row.valid_to,
          tx_from: it.row.tx_from, tx_counter: it.row.tx_counter, tx_node: it.row.tx_node, tx_to: it.row.tx_to,
          type_constraint: it.row.type_constraint, confidence: it.row.confidence,
          security_label: it.row.security_label, status: it.row.status,
          scope_type: it.row.scope_type, scope_id: it.row.scope_id, author: it.row.author,
          epistemic_class: it.row.epistemic_class, fts_tokens: it.row.fts_tokens,
          embedding_blob: it.row.embedding_blob ? Buffer.from(it.row.embedding_blob).toString('base64') : null,
        });
      } else {
        tombstones.push({
          id: it.row.id, subject: it.row.subject, predicate: it.row.predicate,
          scope_type: it.row.scope_type, scope_id: it.row.scope_id,
          tx_from: it.row.tx_from, tx_counter: it.row.tx_counter, tx_node: it.row.tx_node,
          origin: it.row.origin,
        });
      }
    }
    return {
      fromNodeId: this.nodeId,
      versions,
      tombstones,
      nextCursor: { phys: lastHlc.physical, counter: lastHlc.counter, node: lastHlc.nodeId },
      complete: scanned <= req.max,
    };
  }

  // --- Pulling (fetch + merge a peer's deltas) ------------------------------

  async pullPeer(peer: ReplicationPeer): Promise<number> {
    const key = peer.nodeId;
    const cur = (this.db.prepare(`SELECT cur_phys, cur_counter, cur_node FROM memory_sync_cursor WHERE peer_key = ?`).get(key) as any);
    const since: HlcCursor = cur ? { phys: cur.cur_phys, counter: cur.cur_counter, node: cur.cur_node } : { phys: 0, counter: 0, node: '' };
    // Agnostic scope derivation: if the peer declares explicit scopes, honour
    // them (back-compat); otherwise derive the scopes to replicate from the
    // peer's presence + local subject (docs/dsh/08-...).
    const localUser = this.tenantContext.startsWith('user:') ? this.tenantContext.slice('user:'.length) : '';
    const scopes = (peer.scopes && peer.scopes.length)
      ? peer.scopes
      : deriveScopes(this.wantScopes, await this.fetchPresence(peer), localUser);
    if (scopes.length === 0) { return 0; }
    const base = peer.endpoint.startsWith('http') ? peer.endpoint : `http://${peer.endpoint}`;
    const url = `${base}/mesh/memory/sync`;
    const payload = { fromNodeId: this.nodeId, since, scopes, max: this.maxVersions, timestamp: Date.now() };
    const body = JSON.stringify(payload);
    const token = this.makeGrant(peer, since, scopes);

    const dataText = await this.post(url, body, {
      'Content-Type': 'application/json',
      'X-DSH-CAP': encodeToken(token),
      'X-DSH-BODY-HMAC': hmac(this.secret, body),
    });
    const data = safeParse(dataText) as SyncDeltaResponse | null;
    if (!data || !Array.isArray(data.versions)) {
      throw new Error(`Peer ${peer.nodeId} returned malformed delta`);
    }
    let applied = 0;
    applied += this.consumeVersions(data.versions);
    for (const t of data.tombstones || []) {
      applied += this.applyReplicatedTombstone(t);
    }
    // Cursor advances to the server's nextCursor (past filtered versions too).
    const nc = data.nextCursor || since;
    this.db.prepare(`
      INSERT INTO memory_sync_cursor (peer_key, cur_phys, cur_counter, cur_node)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(peer_key) DO UPDATE SET
        cur_phys = MAX(cur_phys, excluded.cur_phys),
        cur_counter = MAX(cur_counter, excluded.cur_counter),
        cur_node = excluded.cur_node
    `).run(key, nc.phys, nc.counter, nc.node);
    return data.complete ? applied : applied + (await this.pullPeer(peer));
  }

  /** Union-CRDT ingest with cluster-wide Axiom immutability (I3/I-SEC5). */
  private consumeVersions(versions: ReplicatedVersion[]): number {
    let applied = 0;
    const insert = this.db.prepare(`
      INSERT OR IGNORE INTO facts (
        id, subject, predicate, object, fts_tokens,
        valid_from, valid_to, tx_from, tx_to, tx_counter, tx_node,
        type_constraint, confidence, security_label, status,
        scope_type, scope_id, author, epistemic_class, embedding_blob
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);
    this.db.exec('BEGIN');
    try {
      for (const v of versions) {
        // Axiom immutability at merge:
        //  - A lower-class version (evidence/hypothesis) can never override an
        //    existing Axiom on the same proposition slot.
        //  - A conflicting Axiom (different object) from a non-origin can never
        //    supersede an existing Axiom on the same slot.
        const existingAxiom = this.db.prepare(`
          SELECT object, tx_node FROM facts
          WHERE subject = ? AND predicate = ? AND scope_type = ? AND scope_id = ?
            AND epistemic_class = 'axiom' AND status = 'active'
        `).get(v.subject, v.predicate, v.scope_type, v.scope_id) as any;
        if (existingAxiom) {
          // Axiom immutability (I3/I-SEC5): a lower-class version can never
          // override a live Axiom, and a conflicting Axiom (different object)
          // can never supersede it either — correction requires retract+reingest.
          if (v.epistemic_class !== 'axiom') continue;
          if (existingAxiom.object !== v.object) continue;
        }
        // Cross-node axiom-creation guards (only origin/admin, enforced in storeFact locally)
        const blob = v.embedding_blob ? Buffer.from(v.embedding_blob, 'base64') : null;
        const res = insert.run(
          v.id, v.subject, v.predicate, v.object, v.fts_tokens || '',
          v.valid_from, v.valid_to, v.tx_from, v.tx_to, v.tx_counter, v.tx_node,
          v.type_constraint, v.confidence, v.security_label, v.status,
          v.scope_type, v.scope_id, v.author, v.epistemic_class || 'evidence', blob,
        );
        applied += Number(res.changes ?? 0);
      }
      this.db.exec('COMMIT');
    } catch (e) {
      this.db.exec('ROLLBACK');
      throw e;
    }
    return applied;
  }

  private applyReplicatedTombstone(t: ReplicatedTombstone): number {
    const res = this.db.prepare(`
      INSERT OR IGNORE INTO memory_tombstones (
        id, subject, predicate, scope_type, scope_id, tx_from, tx_counter, tx_node, origin, tombstone_status
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, '0')
    `).run(t.id, t.subject, t.predicate, t.scope_type, t.scope_id, t.tx_from, t.tx_counter, t.tx_node, t.origin);
    // Upgrade affected active (non-axiom) facts to retracted if they precede the tombstone.
    const upd = this.db.prepare(`
      UPDATE facts SET status = 'retracted', tx_to = ?
      WHERE subject = ? AND predicate = ? AND scope_type = ? AND scope_id = ?
        AND status IN ('active','disputed') AND epistemic_class != 'axiom'
        AND (tx_from, tx_counter, tx_node) < (?, ?, ?)
    `);
    const info = upd.run(t.tx_from, t.subject, t.predicate, t.scope_type, t.scope_id, t.tx_from, t.tx_counter, t.tx_node);
    return Number(info.changes ?? 0);
  }

  startPullLoop(intervalMs: number): void {
    if (this.timer) return;
    this.timer = setInterval(() => {
      void (async () => {
        for (const peer of this.peerNodes) {
          const dir = peer.direction || 'bidirectional';
          if (dir === 'push') continue;
          try { await this.pullPeer(peer); } catch { /* non-fatal */ }
        }
      })();
    }, intervalMs);
  }

  async syncAll(): Promise<void> {
    for (const peer of this.peerNodes) {
      const dir = peer.direction || 'bidirectional';
      if (dir === 'push') continue;
      try { await this.pullPeer(peer); } catch { /* non-fatal */ }
    }
  }

  private get(urlStr: string, headers: Record<string, string>): Promise<string> {
    return new Promise((resolve, reject) => {
      const url = new URL(urlStr);
      const req = http.request(
        {
          hostname: url.hostname,
          port: url.port || 80,
          path: url.pathname,
          method: 'GET',
          headers,
          timeout: 10000,
        },
        (res) => {
          let resData = '';
          res.on('data', (d) => { resData += d; });
          res.on('end', () => {
            if (res.statusCode && res.statusCode >= 200 && res.statusCode < 300) resolve(resData);
            else reject(new Error(`Presence HTTP ${res.statusCode}: ${resData}`));
          });
        },
      );
      req.on('error', reject);
      req.on('timeout', () => { req.destroy(); reject(new Error('Presence timeout')); });
      req.end();
    });
  }

  private post(urlStr: string, body: string, headers: Record<string, string>): Promise<string> {
    return new Promise((resolve, reject) => {
      const url = new URL(urlStr);
      const req = http.request(
        {
          hostname: url.hostname,
          port: url.port || 80,
          path: url.pathname,
          method: 'POST',
          headers: { ...headers, 'Content-Length': Buffer.byteLength(body) },
          timeout: 10000,
        },
        (res) => {
          let resData = '';
          res.on('data', (d) => { resData += d; });
          res.on('end', () => {
            if (res.statusCode && res.statusCode >= 200 && res.statusCode < 300) resolve(resData);
            else reject(new Error(`Sync HTTP ${res.statusCode}: ${resData}`));
          });
        },
      );
      req.on('error', reject);
      req.on('timeout', () => { req.destroy(); reject(new Error('Sync timeout')); });
      req.write(body);
      req.end();
    });
  }

  close(): void {
    if (this.timer) clearInterval(this.timer);
    this.server?.close();
  }
}

function safeParse(s: string): any {
  try { return JSON.parse(s); } catch { return null; }
}
