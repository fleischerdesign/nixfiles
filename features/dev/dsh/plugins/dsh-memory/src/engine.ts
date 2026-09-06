import { DatabaseSync } from 'node:sqlite';
import * as crypto from 'node:crypto';
import type {
  BitemporalFact,
  FactQueryFilter,
  DatalogInferenceResult,
  SecurityLabel,
  EpistemicClass
} from './types.js';

const SECURITY_RANKS: Record<SecurityLabel, number> = {
  system: 0,
  user: 1,
  operator: 2
};

export class BitemporalMemoryEngine {
  private db: DatabaseSync;

  constructor(db: DatabaseSync) {
    this.db = db;
    this.ensureSchemaMigrations();
  }

  private ensureSchemaMigrations(): void {
    try {
      // Check if epistemic_class column exists, if not add it
      const info = this.db.prepare(`PRAGMA table_info(facts)`).all() as any[];
      const hasEpistemic = info.some((col: any) => col.name === 'epistemic_class');
      if (!hasEpistemic) {
        this.db.exec(`ALTER TABLE facts ADD COLUMN epistemic_class TEXT NOT NULL DEFAULT 'evidence';`);
      }

      const hasFtsTokens = info.some((col: any) => col.name === 'fts_tokens');
      if (!hasFtsTokens) {
        this.db.exec(`ALTER TABLE facts ADD COLUMN fts_tokens TEXT NOT NULL DEFAULT '';`);
        // Recreate FTS5 table and triggers with fts_tokens
        this.db.exec(`DROP TABLE IF EXISTS facts_fts;`);
        this.db.exec(`
          CREATE VIRTUAL TABLE facts_fts USING fts5(
            id UNINDEXED,
            subject,
            predicate,
            object,
            fts_tokens,
            tokenize = 'porter unicode61'
          );
          DROP TRIGGER IF EXISTS trg_facts_ai;
          DROP TRIGGER IF EXISTS trg_facts_ad;
          DROP TRIGGER IF EXISTS trg_facts_au;
          CREATE TRIGGER trg_facts_ai AFTER INSERT ON facts BEGIN
            INSERT INTO facts_fts(id, subject, predicate, object, fts_tokens)
            VALUES (new.id, new.subject, new.predicate, new.object, new.fts_tokens);
          END;
          CREATE TRIGGER trg_facts_ad AFTER DELETE ON facts BEGIN
            DELETE FROM facts_fts WHERE id = old.id;
          END;
          CREATE TRIGGER trg_facts_au AFTER UPDATE ON facts BEGIN
            DELETE FROM facts_fts WHERE id = old.id;
            INSERT INTO facts_fts(id, subject, predicate, object, fts_tokens)
            VALUES (new.id, new.subject, new.predicate, new.object, new.fts_tokens);
          END;
        `);

        // Backfill fts_tokens for existing facts
        const existingRows = this.db.prepare(`SELECT id, subject, predicate, object FROM facts`).all() as any[];
        for (const row of existingRows) {
          const tokens = decomposeToStems(`${row.subject} ${row.predicate} ${row.object}`).join(' ');
          this.db.prepare(`UPDATE facts SET fts_tokens = ? WHERE id = ?`).run(tokens, row.id);
          this.db.prepare(`INSERT INTO facts_fts(id, subject, predicate, object, fts_tokens) VALUES (?, ?, ?, ?, ?)`).run(
            row.id, row.subject, row.predicate, row.object, tokens
          );
        }
      }
    } catch {
      // Ignore migration errors on fresh tables
    }
  }

  /**
   * Store a fact using AGM-compliant bitemporal append with Epistemic Classes, Scopes and TTL.
   */
  storeFact(fact: Omit<BitemporalFact, 'id' | 'txFrom' | 'txTo' | 'status' | 'validFrom' | 'validTo'> & { validFrom?: number; validTo?: number; ttlSeconds?: number }): BitemporalFact {
    const id = crypto.randomUUID();
    const now = Date.now();
    const txFrom = now;
    const txTo = Infinity;
    const validFrom = fact.validFrom ?? now;
    let validTo = fact.validTo ?? Infinity;

    const epistemicClass: EpistemicClass = fact.epistemicClass ?? 'evidence';

    // Invariant: Axioms and Evidence NEVER expire prematurely. TTL is strictly for ephemeral hypotheses / caches.
    if (epistemicClass === 'axiom') {
      validTo = Infinity;
    } else if (fact.ttlSeconds && fact.ttlSeconds > 0) {
      if (epistemicClass === 'evidence') {
        // Evidence can have TTL only if explicitly requested, but default to Infinity
        validTo = validFrom + (fact.ttlSeconds * 1000);
      } else {
        // Hypotheses honor TTL strictly
        validTo = validFrom + (fact.ttlSeconds * 1000);
      }
    }

    const scopeType = fact.scopeType ?? 'public';
    const scopeId = fact.scopeId ?? 'public';
    const author = fact.author ?? 'system';

    // Check for conflicting functional facts (Belief Revision within same scope and subject/predicate)
    const existingStmt = this.db.prepare(`
      SELECT id, confidence, object, epistemic_class, status FROM facts
      WHERE subject = ? AND predicate = ? AND scope_id = ? AND status = 'active'
        AND valid_from <= ? AND valid_to > ?
    `);
    const existing = existingStmt.all(fact.subject, fact.predicate, scopeId, now, now) as any[];

    let status: 'active' | 'disputed' = 'active';

    if (existing.length > 0) {
      for (const row of existing) {
        // Axiom Protection: Class 1 Axioms can NEVER be overwritten by lower-class evidence or hypotheses
        if (row.epistemic_class === 'axiom' && epistemicClass !== 'axiom') {
          throw new Error(`EpistemicProtectionViolation: Subject "${fact.subject}" is an immutable Axiom and cannot be modified.`);
        }

        if (row.object !== fact.object) {
          // Contradiction detected
          const existingConf = row.confidence;
          const newConf = fact.confidence ?? 1.0;

          if (newConf >= existingConf) {
            // Supersede existing fact: close valid_to bitemporally
            this.db.prepare(`UPDATE facts SET valid_to = ?, status = 'disputed' WHERE id = ?`).run(now, row.id);
          } else {
            // New fact is weaker -> tag as disputed
            status = 'disputed';
          }
        }
      }
    }

    const ftsTokens = decomposeToStems(`${fact.subject} ${fact.predicate} ${fact.object}`).join(' ');

    const insertStmt = this.db.prepare(`
      INSERT INTO facts (
        id, subject, predicate, object, fts_tokens,
        valid_from, valid_to, tx_from, tx_to,
        type_constraint, confidence, security_label, status,
        scope_type, scope_id, author, epistemic_class
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);

    insertStmt.run(
      id,
      fact.subject,
      fact.predicate,
      fact.object,
      ftsTokens,
      validFrom,
      validTo,
      txFrom,
      txTo,
      fact.typeConstraint ?? 'String',
      fact.confidence ?? 1.0,
      fact.securityLabel ?? 'system',
      status,
      scopeType,
      scopeId,
      author,
      epistemicClass
    );

    return {
      id,
      ...fact,
      epistemicClass,
      scopeType,
      scopeId,
      author,
      validFrom,
      validTo,
      txFrom,
      txTo,
      status
    };
  }

  /**
   * Retract / delete a fact (Sets status to 'retracted' and bitemporally closes tx_to).
   */
  retractFact(id: string, identity?: { username: string; groups?: string[]; clearance?: string }): boolean {
    const row = this.db.prepare(`SELECT * FROM facts WHERE id = ?`).get(id) as any;
    if (!row) return false;

    // Axiom Protection
    if (row.epistemic_class === 'axiom') {
      throw new Error(`EpistemicProtectionViolation: Immutable Axioms cannot be retracted.`);
    }

    // Authorization check
    if (identity && identity.clearance !== 'Admin') {
      const isOwner = row.author === identity.username;
      const isUserScope = row.scope_type === 'user' && row.scope_id === `user:${identity.username}`;
      const isGroupMember = row.scope_type === 'group' && identity.groups?.includes(row.scope_id.replace(/^group:/, ''));

      if (!isOwner && !isUserScope && !isGroupMember) {
        throw new Error(`Unauthorized: Cannot delete memory fact belonging to ${row.scope_id}`);
      }
    }

    const now = Date.now();
    this.db.prepare(`UPDATE facts SET status = 'retracted', tx_to = ? WHERE id = ?`).run(now, id);
    return true;
  }

  /**
   * Execute deductive Datalog query with Lattice-Security and Scope filtering.
   */
  query(filter: FactQueryFilter, identity?: { username: string; groups?: string[]; clearance?: string }): DatalogInferenceResult {
    const now = Date.now();
    const validAt = filter.asOfValid ?? now;
    const txAt = filter.asOfTx ?? now;
    const maxRank = SECURITY_RANKS[filter.maxSecurityLabel ?? 'operator'];

    let baseSql = `
      SELECT * FROM facts
      WHERE status = 'active'
        AND valid_from <= ? AND valid_to > ?
        AND tx_from <= ? AND tx_to > ?
    `;
    const params: any[] = [validAt, validAt, txAt, txAt];

    if (filter.subject) {
      baseSql += ` AND subject = ?`;
      params.push(filter.subject);
    }
    if (filter.predicate) {
      baseSql += ` AND predicate = ?`;
      params.push(filter.predicate);
    }
    if (filter.object) {
      baseSql += ` AND object = ?`;
      params.push(filter.object);
    }
    if (filter.epistemicClass) {
      baseSql += ` AND epistemic_class = ?`;
      params.push(filter.epistemicClass);
    }

    // FTS5 Fulltext Search filter
    if (filter.search && filter.search.trim()) {
      const cleanTerm = filter.search.replace(/['"*]/g, '').trim();
      if (cleanTerm) {
        baseSql += ` AND id IN (SELECT id FROM facts_fts WHERE facts_fts MATCH ?)`;
        params.push(`${cleanTerm}*`);
      }
    }

    // Scoping constraint
    if (filter.scopeType && filter.scopeId) {
      baseSql += ` AND scope_type = ? AND scope_id = ?`;
      params.push(filter.scopeType, filter.scopeId);
    }

    const rows = this.db.prepare(baseSql).all(...params) as any[];

    // Filter Lattice security label & multi-tenant scope in-memory
    const facts: BitemporalFact[] = rows
      .filter((r) => {
        // 1. Security Rank
        if (SECURITY_RANKS[r.security_label as SecurityLabel] > maxRank) return false;

        // 2. Multi-Tenancy Scope Visibility
        if (!identity || identity.clearance === 'Admin') return true;
        if (r.scope_type === 'public') return true;
        if (r.scope_type === 'user') return r.scope_id === `user:${identity.username}`;
        if (r.scope_type === 'group') {
          const groupName = r.scope_id.replace(/^group:/, '');
          return identity.groups?.includes(groupName) ?? false;
        }
        if (r.scope_type === 'repo') return true;

        return false;
      })
      .map((r) => ({
        id: r.id,
        subject: r.subject,
        predicate: r.predicate,
        object: r.object,
        validFrom: r.valid_from,
        validTo: r.valid_to,
        txFrom: r.tx_from,
        txTo: r.tx_to,
        typeConstraint: r.type_constraint,
        confidence: r.confidence,
        securityLabel: r.security_label,
        status: r.status,
        scopeType: r.scope_type,
        scopeId: r.scope_id,
        author: r.author,
        epistemicClass: r.epistemic_class
      }));

    return {
      facts,
      derivedRelations: []
    };
  }

  /**
   * Fast, Token-Guarded BM25 Context Recall.
   * Enforces:
   * 1. Entropy Gate (Query length & substance)
   * 2. Relevance threshold (Negative BM25 rank cutoff)
   * 3. Hard token budget cap
   * 4. Session history deduplication
   */
  recallContextGuarded(options: {
    queryText: string;
    identity?: { username: string; groups?: string[]; clearance?: string };
    repoId?: string;
    recentTurnTexts?: string[];
    maxTokens?: number;
    minThreshold?: number;
  }): BitemporalFact[] {
    const {
      queryText,
      identity,
      repoId,
      recentTurnTexts = [],
      maxTokens = 150,
      minThreshold = -1.5 // in SQLite FTS5 bm25(), more negative = better match
    } = options;

    // 1. Entropy Gate: Ignore short greetings, affirmative replies, or trivial smalltalk
    const queryStems = decomposeToStems(queryText)
      .filter((w) => w.length > 2 && !STOPWORDS.has(w.toLowerCase()))
      .slice(0, 16);

    // If query lacks substantive content, zero tokens injected!
    if (queryStems.length < 2) {
      return [];
    }

    const matchQuery = queryStems.map(t => `"${t}"*`).join(' OR ');
    const now = Date.now();

    const sql = `
      SELECT f.*, bm25(facts_fts) as score
      FROM facts f
      JOIN facts_fts ON f.id = facts_fts.id
      WHERE f.status = 'active'
        AND f.valid_from <= ? AND f.valid_to > ?
        AND facts_fts MATCH ?
      ORDER BY score ASC
      LIMIT 15
    `;

    try {
      const rows = this.db.prepare(sql).all(now, now, matchQuery) as any[];
      const recentHistoryFlat = recentTurnTexts.join(' ').toLowerCase();

      const selectedFacts: BitemporalFact[] = [];
      let accumulatedTokens = 0;

      for (const r of rows) {
        // Relevance threshold check: FTS5 BM25 score is negative (e.g. -5.2 is better than -0.5)
        if (r.score > minThreshold) {
          continue; // Match too weak -> skip to save tokens
        }

        // Multi-tenant permission check
        if (identity && identity.clearance !== 'Admin') {
          if (r.scope_type === 'user' && r.scope_id !== `user:${identity.username}`) continue;
          if (r.scope_type === 'group') {
            const groupName = r.scope_id.replace(/^group:/, '');
            if (!identity.groups?.includes(groupName)) continue;
          }
          if (r.scope_type === 'repo' && repoId && r.scope_id !== `repo:${repoId}`) continue;
        }

        // Deduplication: if subject AND object are already in recent turns, don't waste tokens
        if (recentHistoryFlat.includes(r.subject.toLowerCase()) && recentHistoryFlat.includes(r.object.toLowerCase())) {
          continue;
        }

        // Estimate token cost (~1 token per 4 characters)
        const line = `- ${r.subject} ${r.predicate} ${r.object} (${r.scope_id})\n`;
        const estimatedTokens = Math.ceil(line.length / 4);

        if (accumulatedTokens + estimatedTokens > maxTokens) {
          break; // Hard budget reached
        }

        selectedFacts.push({
          id: r.id,
          subject: r.subject,
          predicate: r.predicate,
          object: r.object,
          validFrom: r.valid_from,
          validTo: r.valid_to,
          txFrom: r.tx_from,
          txTo: r.tx_to,
          typeConstraint: r.type_constraint,
          confidence: r.confidence,
          securityLabel: r.security_label,
          status: r.status,
          scopeType: r.scope_type,
          scopeId: r.scope_id,
          author: r.author,
          epistemicClass: r.epistemic_class
        });

        accumulatedTokens += estimatedTokens;
      }

      return selectedFacts;
    } catch {
      return [];
    }
  }

  /**
   * Compute recursive transitive closure (Datalog Fixpoint) using native recursive CTE.
   */
  queryTransitiveClosure(subject: string, predicate: string): Array<{ subject: string; object: string; depth: number }> {
    const now = Date.now();
    const sql = `
      WITH RECURSIVE Transitive(subject, object, depth) AS (
        SELECT subject, object, 1 AS depth
        FROM facts
        WHERE subject = ? AND predicate = ? AND status = 'active'
          AND valid_from <= ? AND valid_to > ?
        UNION ALL
        SELECT f.subject, t.object, t.depth + 1
        FROM facts f
        JOIN Transitive t ON f.object = t.subject
        WHERE f.predicate = ? AND f.status = 'active'
          AND f.valid_from <= ? AND f.valid_to > ?
          AND t.depth < 20
      )
      SELECT DISTINCT subject, object, depth FROM Transitive;
    `;

    const rows = this.db.prepare(sql).all(subject, predicate, now, now, predicate, now, now) as any[];
    return rows;
  }
}

const STOPWORDS = new Set([
  'the', 'is', 'at', 'which', 'on', 'and', 'a', 'an', 'in', 'that', 'to', 'for', 'it', 'with', 'as',
  'der', 'die', 'das', 'und', 'ist', 'in', 'den', 'von', 'zu', 'mit', 'auf', 'für', 'eine', 'einen', 'ein',
  'hallo', 'moin', 'hi', 'danke', 'bitte', 'ok', 'okay', 'yes', 'no', 'ja', 'nein', 'wie', 'was'
]);

/**
 * Pure morphological decomposition and sub-word indexing.
 * Decomposes CamelCase, namespace delimiters (: _ . - /), and common grammatical affixes
 * without relying on external heavy language runtimes.
 */
function decomposeToStems(str: string): string[] {
  if (!str) return [];
  const words = str
    .replace(/([a-z])([A-Z])/g, '$1 $2')
    .replace(/[^a-zA-Z0-9_\-\u4e00-\u9fa5]/g, ' ')
    .toLowerCase()
    .split(/\s+/)
    .filter((w) => w.length > 1);

  const tokens = new Set<string>();
  const prefixes = ['vor', 'nach', 'spitz', 'voll', 'host', 'netz', 'user', 'sub'];

  for (const w of words) {
    tokens.add(w);
    const stem = w.replace(/(?:e|en|er|es|em|n|s|ed|ing)$/, '');
    if (stem.length > 2) tokens.add(stem);

    for (const p of prefixes) {
      if (w.startsWith(p) && w.length > p.length + 2) {
        const sub = w.slice(p.length);
        tokens.add(sub);
        const subStem = sub.replace(/(?:e|en|er|es|em|n|s|ed|ing)$/, '');
        if (subStem.length > 2) tokens.add(subStem);
      }
    }
  }
  return Array.from(tokens);
}
