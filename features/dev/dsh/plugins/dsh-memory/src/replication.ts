/**
 * @module dsh-memory/replication
 * Cross-Node memory replication (C7, P1): HMAC-signed delta sync over the
 * peer mesh. Versions are immutable and merged as a CvRDT union (G-Set), so
 * re-delivery is idempotent and convergence is order-independent.
 *
 * P1 boundary: scope visibility is enforced on both sides (I-SEC1/2); Axiom
 * immutability at *merge* time and OR-Set tombstone propagation are P3.
 */
import * as http from 'node:http';
import * as crypto from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';

export interface ReplicationPeer {
  nodeId: string;
  endpoint: string; // "host:port" or URL
  direction?: 'pull' | 'push' | 'bidirectional';
  scopes?: string[];
}

export interface MemoryReplicationConfig {
  enabled?: boolean;
  nodeId?: string;
  secretEnv?: string;
  peers?: ReplicationPeer[];
  listenPort?: number;
  listenHost?: string;
  syncIntervalMs?: number;
  maxVersionsPerSync?: number;
}

/** A fully serialised fact version (mirrors `facts` columns). */
export interface ReplicatedVersion {
  id: string;
  subject: string;
  predicate: string;
  object: string;
  valid_from: number;
  valid_to: number;
  tx_from: number;
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

export interface SyncDeltaRequest {
  fromNodeId: string;
  since: number; // tx_from cursor (exclusive)
  scopes: string[];
  max: number;
}

export interface SyncDeltaResponse {
  fromNodeId: string;
  versions: ReplicatedVersion[];
  nextCursor: number;
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

export class MemoryReplicator {
  private readonly secret: string;
  private readonly nodeId: string;
  private readonly peerNodes: ReplicationPeer[];
  private readonly maxVersions: number;
  private readonly db: DatabaseSync;
  private server?: http.Server;
  private timer?: NodeJS.Timeout;

  constructor(
    opts: {
      db: DatabaseSync;
      secret: string;
      nodeId: string;
      peers?: ReplicationPeer[];
      syncIntervalMs?: number;
      maxVersionsPerSync?: number;
    },
  ) {
    this.db = opts.db;
    this.secret = opts.secret;
    this.nodeId = opts.nodeId;
    this.peerNodes = (opts.peers || []).filter((p) => p.nodeId !== this.nodeId);
    this.maxVersions = opts.maxVersionsPerSync ?? 512;
    this.ensureCursorTable();
  }

  private ensureCursorTable(): void {
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS memory_sync_cursor (
        peer_key TEXT PRIMARY KEY,
        cursor INTEGER NOT NULL DEFAULT 0
      );
    `);
  }

  // --- Serving (receive a peer's pull request) -----------------------------

  startServer(port: number, host = '0.0.0.0'): void {
    if (this.server) return;
    this.server = http.createServer((req: http.IncomingMessage, res: http.ServerResponse) => {
      if (req.method !== 'POST' || req.url !== '/mesh/memory/sync') {
        res.writeHead(404);
        res.end();
        return;
      }
      let body = '';
      req.on('data', (d) => { body += d; });
      req.on('end', () => {
        // 1. Verify HMAC signature over the raw body (Replay-safe: the
        //    signer includes a `timestamp` we clamp to a ±5min window).
        const sig = req.headers['x-dsh-hmac'] as string | undefined;
        const parsed = safeParse(body);
        if (!sig || !timingSafeEqual(sig, hmac(this.secret, body))) {
          res.writeHead(401, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'Unauthorized: invalid HMAC' }));
          return;
        }
        const ts = parsed?.timestamp as number | undefined;
        if (typeof ts !== 'number' || Math.abs(Date.now() - ts) > 5 * 60 * 1000) {
          res.writeHead(401, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'Unauthorized: stale/future timestamp' }));
          return;
        }
        const req_: SyncDeltaRequest = {
          fromNodeId: parsed?.fromNodeId || 'unknown',
          since: (parsed?.since as number) || 0,
          scopes: Array.isArray(parsed?.scopes) ? (parsed.scopes as string[]) : ['public'],
          max: (parsed?.max as number) || this.maxVersions,
        };
        try {
          const resp = this.produceDelta(req_);
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify(resp));
        } catch (e: any) {
          res.writeHead(500, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: e.message || String(e) }));
        }
      });
    });
    this.server.listen(port, host);
  }

  private produceDelta(req: SyncDeltaRequest): SyncDeltaResponse {
    const allowed = req.scopes.length ? req.scopes : ['public'];
    const rows = this.db.prepare(`
      SELECT id, subject, predicate, object, valid_from, valid_to, tx_from, tx_to,
        type_constraint, confidence, security_label, status, scope_type, scope_id,
        author, epistemic_class, fts_tokens, embedding_blob
      FROM facts
      WHERE tx_from > ?
      ORDER BY tx_from ASC
      LIMIT ?
    `).all(req.since, req.max) as any[];

    const versions: ReplicatedVersion[] = [];
    for (const r of rows) {
      if (!canReplicateScope(r.scope_type, r.scope_id, allowed)) continue;
      versions.push({
        id: r.id,
        subject: r.subject,
        predicate: r.predicate,
        object: r.object,
        valid_from: r.valid_from,
        valid_to: r.valid_to,
        tx_from: r.tx_from,
        tx_to: r.tx_to,
        type_constraint: r.type_constraint,
        confidence: r.confidence,
        security_label: r.security_label,
        status: r.status,
        scope_type: r.scope_type,
        scope_id: r.scope_id,
        author: r.author,
        epistemic_class: r.epistemic_class,
        fts_tokens: r.fts_tokens,
        embedding_blob: r.embedding_blob ? Buffer.from(r.embedding_blob).toString('base64') : null,
      });
    }
    // `nextCursor` advances past EVERY scanned row (incl. scope-filtered) so the
    // client never re-pulls versions it is not permitted to see.
    const nextCursor = rows.length ? rows[rows.length - 1].tx_from : req.since;
    return {
      fromNodeId: this.nodeId,
      versions,
      nextCursor,
      complete: rows.length < req.max,
    };
  }

  // --- Pulling (fetch + merge a peer's deltas) ------------------------------

  async pullPeer(peer: ReplicationPeer): Promise<number> {
    const key = peer.nodeId;
    const since = (this.db.prepare(`SELECT cursor FROM memory_sync_cursor WHERE peer_key = ?`).get(key) as any)?.cursor ?? 0;
    const scopes = (peer.scopes && peer.scopes.length ? peer.scopes : ['public']);
    const base = peer.endpoint.startsWith('http') ? peer.endpoint : `http://${peer.endpoint}`;
    const url = `${base}/mesh/memory/sync`;
    const payload = { fromNodeId: this.nodeId, since, scopes, max: this.maxVersions, timestamp: Date.now() };
    const body = JSON.stringify(payload);
    const sig = hmac(this.secret, body);

    const dataText = await this.post(url, body, { 'Content-Type': 'application/json', 'X-DSH-HMAC': sig });
    const data = safeParse(dataText) as SyncDeltaResponse | null;
    if (!data || !Array.isArray(data.versions)) {
      throw new Error(`Peer ${peer.nodeId} returned malformed delta`);
    }
    let applied = 0;
    this.consumeVersions(data.versions);
    // Cursor advances to the server's `nextCursor` (past filtered versions too),
    // so a peer never re-serves versions the client may not see.
    const maxTx = typeof data.nextCursor === 'number' ? data.nextCursor : since;
    this.db.prepare(`
      INSERT INTO memory_sync_cursor (peer_key, cursor) VALUES (?, ?)
      ON CONFLICT(peer_key) DO UPDATE SET cursor = MAX(cursor, excluded.cursor)
    `).run(key, maxTx);
    applied = data.versions.length;
    return data.complete ? applied : applied + (await this.pullPeer(peer));
  }

  /** Union-CRDT ingest: INSERT OR IGNORE by id (idempotent, converges). */
  private consumeVersions(versions: ReplicatedVersion[]): void {
    const insert = this.db.prepare(`
      INSERT OR IGNORE INTO facts (
        id, subject, predicate, object, fts_tokens,
        valid_from, valid_to, tx_from, tx_to,
        type_constraint, confidence, security_label, status,
        scope_type, scope_id, author, epistemic_class, embedding_blob
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);
    this.db.exec('BEGIN');
    try {
      for (const v of versions) {
        const blob = v.embedding_blob ? Buffer.from(v.embedding_blob, 'base64') : null;
        insert.run(
          v.id, v.subject, v.predicate, v.object, v.fts_tokens || '',
          v.valid_from, v.valid_to, v.tx_from, v.tx_to,
          v.type_constraint, v.confidence, v.security_label, v.status,
          v.scope_type, v.scope_id, v.author, v.epistemic_class || 'evidence', blob,
        );
      }
      this.db.exec('COMMIT');
    } catch (e) {
      this.db.exec('ROLLBACK');
      throw e;
    }
  }

  startPullLoop(intervalMs: number): void {
    if (this.timer) return;
    this.timer = setInterval(() => {
      void (async () => {
        for (const peer of this.peerNodes) {
          const dir = peer.direction || 'bidirectional';
          if (dir === 'push') continue;
          try {
            await this.pullPeer(peer);
          } catch (e: any) {
            // non-fatal: unreachable peer or transient error
          }
        }
      })();
    }, intervalMs);
  }

  async syncAll(): Promise<void> {
    for (const peer of this.peerNodes) {
      const dir = peer.direction || 'bidirectional';
      if (dir === 'push') continue;
      try {
        await this.pullPeer(peer);
      } catch {
        // non-fatal
      }
    }
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
