/**
 * @module dsh-auth/presence
 * Tenant-Presence-Registry: records which OIDC tenants (username + groups) have
 * authenticated on this instance. Feeds the mesh presence advertisement used for
 * agnostic memory-scope peer derivation (docs/dsh/08-multi-instance-mesh-sync.md).
 *
 * Presence is an *approximation* (only identities that have been seen at least
 * once), persisted in a small SQLite DB rooted at `DSH_HOME/auth/presence.db`.
 */
import { DatabaseSync, type SQLInputValue } from 'node:sqlite';
import * as fs from 'node:fs';
import * as path from 'node:path';
import type { UserIdentity } from './types.js';

export interface PresenceEntry {
  tenantId: string;
  username: string;
  groups: string[];
  lastSeen: number;
}

export class PresenceRegistry {
  private db: DatabaseSync;
  private readonly tenantTtlMs: number;

  constructor(dbPath: string, tenantTtlMs = 90 * 24 * 60 * 60 * 1000) {
    if (dbPath !== ':memory:') {
      const dir = path.dirname(dbPath);
      if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
    }
    this.db = new DatabaseSync(dbPath);
    this.tenantTtlMs = tenantTtlMs;
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS presence (
        tenant_id TEXT PRIMARY KEY,
        username TEXT NOT NULL,
        groups_json TEXT NOT NULL DEFAULT '[]',
        last_seen INTEGER NOT NULL
      );
    `);
  }

  /** Record that `identity` was just authenticated by this instance. */
  noteTenant(identity: UserIdentity): void {
    if (!identity) return;
    const id = identity.id || `usr_${identity.username}`;
    this.db.prepare(`
      INSERT INTO presence (tenant_id, username, groups_json, last_seen)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(tenant_id) DO UPDATE SET
        username = excluded.username,
        groups_json = excluded.groups_json,
        last_seen = MAX(last_seen, excluded.last_seen)
    `).run(id, identity.username, JSON.stringify(identity.groups || []), Date.now());
  }

  /** All currently-present tenants (fs). */
  entries(): PresenceEntry[] {
    const rows = this.db.prepare(`SELECT tenant_id, username, groups_json, last_seen FROM presence`).all() as any[];
    return rows.map((r) => ({
      tenantId: r.tenant_id,
      username: r.username,
      groups: safeParseGroups(r.groups_json),
      lastSeen: r.last_seen,
    }));
  }

  /** The union of groups hosted by present tenants. */
  groups(): string[] {
    const set = new Set<string>();
    for (const e of this.entries()) {
      for (const g of e.groups) set.add(`group:${g}`);
    }
    return Array.from(set);
  }

  /** Username -> group map (for OIDC-subject-equivalence). */
  tenants(): Array<{ tenantId: string; username: string; groups: string[] }> {
    return this.entries().map((e) => ({ tenantId: e.tenantId, username: e.username, groups: e.groups }));
  }

  /** Drop tenants inactive for longer than the TTL (offline judgment). */
  prune(): number {
    const cutoff = Date.now() - this.tenantTtlMs;
    const info = this.db.prepare(`DELETE FROM presence WHERE last_seen < ?`).run(cutoff);
    return Number(info.changes ?? 0);
  }

  close(): void {
    try { this.db.close(); } catch { /* already closed */ }
  }
}

function safeParseGroups(s: string): string[] {
  try {
    const v = JSON.parse(s);
    return Array.isArray(v) ? v.map(String) : [];
  } catch {
    return [];
  }
}
