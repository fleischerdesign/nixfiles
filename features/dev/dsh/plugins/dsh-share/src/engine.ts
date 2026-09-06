import * as crypto from 'node:crypto';
import * as path from 'node:path';
import * as fs from 'node:fs';
import { DatabaseSync } from 'node:sqlite';
import { sanitizeMessagePayload } from './redaction.js';
import type {
  ShareOptions,
  SharedSessionRecord,
  CreateShareResponse,
  ShareAclEntry,
  SessionShareListResponse,
} from './types.js';

export class SessionShareEngine {
  private db: DatabaseSync;
  private hmacKey: Buffer;

  constructor(dshHome?: string) {
    const baseDir = dshHome || process.env.DSH_HOME || path.join(process.env.HOME || '/tmp', '.dsh');
    const storageDir = path.join(baseDir, 'storages');
    fs.mkdirSync(storageDir, { recursive: true });

    const dbPath = path.join(storageDir, 'shares.db');
    this.db = new DatabaseSync(dbPath);
    this.hmacKey = this.resolveSecret(baseDir);

    this.initDatabase();
  }

  private resolveSecret(baseDir: string): Buffer {
    const secretFile = path.join(baseDir, '.share-signing-secret');
    try {
      if (fs.existsSync(secretFile)) {
        return fs.readFileSync(secretFile);
      }
    } catch {
      // Fall through to generation
    }
    const generated = crypto.randomBytes(32);
    try {
      fs.writeFileSync(secretFile, generated, { mode: 0o600 });
    } catch {
      // Ephemeral fallback
    }
    return generated;
  }

  private initDatabase(): void {
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS shared_sessions (
        share_id TEXT PRIMARY KEY,
        token TEXT UNIQUE NOT NULL,
        session_id TEXT NOT NULL,
        owner TEXT NOT NULL,
        title TEXT NOT NULL,
        scope TEXT NOT NULL,
        access_mode TEXT NOT NULL,
        permission TEXT NOT NULL,
        strip_secrets INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        expires_at INTEGER NOT NULL,
        revoked INTEGER NOT NULL DEFAULT 0,
        snapshot_json TEXT
      );

      CREATE INDEX IF NOT EXISTS idx_shared_sessions_session ON shared_sessions(session_id);
      CREATE INDEX IF NOT EXISTS idx_shared_sessions_token ON shared_sessions(token);

      CREATE TABLE IF NOT EXISTS share_acls (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        grantee TEXT NOT NULL,
        permission TEXT NOT NULL,
        granted_at INTEGER NOT NULL,
        UNIQUE(session_id, grantee)
      );

      CREATE INDEX IF NOT EXISTS idx_share_acls_session ON share_acls(session_id);
      CREATE INDEX IF NOT EXISTS idx_share_acls_grantee ON share_acls(grantee);
    `);
  }

  /**
   * Mint an unguessable, HMAC-SHA256 authenticated capability token.
   */
  private generateCapabilityToken(shareId: string, sessionId: string, scope: string): string {
    const rawEntropy = crypto.randomBytes(24).toString('base64url');
    const payload = `${shareId}.${sessionId}.${scope}.${rawEntropy}`;
    const signature = crypto.createHmac('sha256', this.hmacKey).update(payload).digest('base64url');
    return `dsh_sh_${payload}.${signature}`;
  }

  /**
   * Create a new share link or grant ACL.
   */
  public async createShare(
    opts: ShareOptions,
    owner: string,
    title: string,
    rawMessages: any[]
  ): Promise<CreateShareResponse> {
    const shareId = `sh_${crypto.randomUUID()}`;
    const token = this.generateCapabilityToken(shareId, opts.sessionId, opts.scope);
    const createdAt = Date.now();
    const expiresAt = opts.ttlSeconds && opts.ttlSeconds > 0 ? createdAt + opts.ttlSeconds * 1000 : 0;
    const stripSecrets = opts.stripSecrets !== false;

    // Redact snapshot data if in snapshot mode
    let snapshotJson: string | null = null;
    if (opts.accessMode === 'snapshot') {
      const sanitized = stripSecrets ? sanitizeMessagePayload(rawMessages) : rawMessages;
      snapshotJson = JSON.stringify(sanitized);
    }

    const stmt = this.db.prepare(`
      INSERT INTO shared_sessions (
        share_id, token, session_id, owner, title, scope, access_mode,
        permission, strip_secrets, created_at, expires_at, revoked, snapshot_json
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)
    `);

    stmt.run(
      shareId,
      token,
      opts.sessionId,
      owner,
      title,
      opts.scope,
      opts.accessMode,
      opts.permission,
      stripSecrets ? 1 : 0,
      createdAt,
      expiresAt,
      snapshotJson
    );

    // If targeted scopes are specified, grant them to the ACL table as well
    if (opts.scope.startsWith('group:') || opts.scope.startsWith('user:')) {
      this.grantAcl(opts.sessionId, opts.scope, opts.permission);
    }

    return {
      shareId,
      token,
      shareUrl: `/share/${token}`,
      scope: opts.scope,
      permission: opts.permission,
      expiresAt,
    };
  }

  /**
   * Grant direct targeted ACL to a user or group.
   */
  public grantAcl(sessionId: string, grantee: string, permission: 'view' | 'fork' | 'collaborate'): void {
    const stmt = this.db.prepare(`
      INSERT INTO share_acls (session_id, grantee, permission, granted_at)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(session_id, grantee) DO UPDATE SET permission = excluded.permission, granted_at = excluded.granted_at
    `);
    stmt.run(sessionId, grantee, permission, Date.now());
  }

  /**
   * Remove targeted ACL from a user or group.
   */
  public revokeAcl(sessionId: string, grantee: string): void {
    const stmt = this.db.prepare(`DELETE FROM share_acls WHERE session_id = ? AND grantee = ?`);
    stmt.run(sessionId, grantee);
  }

  /**
   * Instant Kill-Switch: Revoke a specific share link.
   */
  public revokeShare(shareId: string): boolean {
    const stmt = this.db.prepare(`UPDATE shared_sessions SET revoked = 1 WHERE share_id = ?`);
    const result = stmt.run(shareId);
    return (result.changes ?? 0) > 0;
  }

  /**
   * Retrieve and evaluate a shared session by its capability token.
   */
  public getShareByToken(
    token: string,
    caller?: { username: string; groups: string[]; clearance?: string }
  ): SharedSessionRecord | null {
    const stmt = this.db.prepare(`
      SELECT * FROM shared_sessions WHERE token = ? AND revoked = 0
    `);
    const row = stmt.get(token) as any;
    if (!row) return null;

    // Check expiration TTL
    if (row.expires_at > 0 && Date.now() > row.expires_at) {
      return null;
    }

    // Lattice-based Access Verification
    if (row.scope !== 'public') {
      if (!caller) return null; // Unauthenticated call to private/group share
      if (caller.clearance === 'Admin') {
        // Admin has universal override
      } else if (row.scope.startsWith('user:')) {
        const requiredUser = row.scope.replace(/^user:/, '');
        if (caller.username !== requiredUser && caller.username !== row.owner) {
          return null;
        }
      } else if (row.scope.startsWith('group:')) {
        const requiredGroup = row.scope.replace(/^group:/, '');
        if (!caller.groups.includes(requiredGroup) && caller.username !== row.owner) {
          return null;
        }
      }
    }

    // Fetch associated ACLs
    const aclRows = this.db
      .prepare(`SELECT grantee, permission, granted_at FROM share_acls WHERE session_id = ?`)
      .all(row.session_id) as any[];

    const acl: ShareAclEntry[] = aclRows.map((r) => ({
      grantee: r.grantee,
      permission: r.permission,
      grantedAt: r.granted_at,
    }));

    return {
      shareId: row.share_id,
      token: row.token,
      sessionId: row.session_id,
      owner: row.owner,
      title: row.title,
      scope: row.scope,
      accessMode: row.access_mode,
      permission: row.permission,
      stripSecrets: row.strip_secrets === 1,
      createdAt: row.created_at,
      expiresAt: row.expires_at,
      revoked: row.revoked === 1,
      acl,
      snapshotData: row.snapshot_json ? JSON.parse(row.snapshot_json) : undefined,
    };
  }

  /**
   * List all active shares and ACLs for a specific session.
   */
  public listSessionShares(sessionId: string): SessionShareListResponse {
    const shareRows = this.db
      .prepare(`
        SELECT share_id, token, scope, permission, created_at, expires_at, revoked
        FROM shared_sessions
        WHERE session_id = ?
        ORDER BY created_at DESC
      `)
      .all(sessionId) as any[];

    const aclRows = this.db
      .prepare(`SELECT grantee, permission, granted_at FROM share_acls WHERE session_id = ? ORDER BY granted_at DESC`)
      .all(sessionId) as any[];

    return {
      shares: shareRows.map((r) => ({
        shareId: r.share_id,
        token: r.token,
        shareUrl: `/share/${r.token}`,
        scope: r.scope,
        permission: r.permission,
        createdAt: r.created_at,
        expiresAt: r.expires_at,
        revoked: r.revoked === 1,
      })),
      acl: aclRows.map((r) => ({
        grantee: r.grantee,
        permission: r.permission,
        grantedAt: r.granted_at,
      })),
    };
  }

  /**
   * List all sessions shared with a specific user or their groups.
   */
  public listSessionsSharedWith(username: string, groups: string[]): Array<{ sessionId: string; permission: string }> {
    const placeholders = groups.map(() => '?').join(', ');
    const query = `
      SELECT DISTINCT session_id, permission
      FROM share_acls
      WHERE grantee = ? ${groups.length > 0 ? `OR grantee IN (${placeholders})` : ''}
    `;
    const params = [
      `user:${username}`,
      ...groups.map((g) => `group:${g}`)
    ];

    const rows = this.db.prepare(query).all(...params) as any[];
    return rows.map((r) => ({
      sessionId: r.session_id,
      permission: r.permission,
    }));
  }
}
