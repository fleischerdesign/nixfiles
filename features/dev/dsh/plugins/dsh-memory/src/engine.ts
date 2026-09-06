import { DatabaseSync } from 'node:sqlite';
import * as crypto from 'node:crypto';
import type {
  BitemporalFact,
  FactQueryFilter,
  DatalogInferenceResult,
  SecurityLabel,
  EpistemicClass
} from './types.js';
import {
  EmbeddingProvider,
  EmbeddingUnavailableError,
  cosine
} from './embedding.js';
import { STOPWORDS, decomposeToStems, floatToBlob, blobToFloat } from './text.js';

const SECURITY_RANKS: Record<SecurityLabel, number> = {
  system: 0,
  user: 1,
  operator: 2
};

/** Normalise an FTS5 bm25() score (negative, more negative = better) into [0, 1). */
function bm25Norm(score: number): number {
  const abs = Math.abs(score);
  return abs / (1 + abs);
}

export class BitemporalMemoryEngine {
  private db: DatabaseSync;
  private readonly embeddingProvider?: EmbeddingProvider;
  private readonly vectorTopK: number;
  private readonly minSimilarity: number;
  private readonly similarityMargin: number;
  private readonly weight: number;
  private readonly decayHalfLifeSeconds: number;
  private readonly decayFloor: number;

  constructor(
    db: DatabaseSync,
    embeddingProvider?: EmbeddingProvider,
    vectorOptions: { topK?: number; minSimilarity?: number; weight?: number; similarityMargin?: number } = {},
    decayOptions: { halfLifeSeconds?: number; floor?: number } = {},
  ) {
    this.db = db;
    this.embeddingProvider = embeddingProvider;
    this.vectorTopK = vectorOptions.topK && vectorOptions.topK > 0 ? vectorOptions.topK : 8;
    this.minSimilarity = vectorOptions.minSimilarity ?? 0;
    this.similarityMargin = vectorOptions.similarityMargin ?? 0.2;
    this.weight = vectorOptions.weight ?? 0.7;
    this.decayHalfLifeSeconds = decayOptions.halfLifeSeconds ?? 0;
    this.decayFloor = decayOptions.floor ?? -1;
    this.ensureSchemaMigrations();
  }

  /**
   * A1 Decay-Governance: the effective confidence is DERIVED (never stored),
   * so it stays deterministic and convergent across nodes. Axioms never decay;
   * evidence/hypothesis decay exponentially with the configured half-life.
   * `exp(−ln2 · age / halfLife)` — the Bayesian term from formal-foundations §4.2.
   */
  effectiveConfidence(fact: { confidence: number; validFrom: number; epistemicClass?: EpistemicClass }, now = Date.now()): number {
    const hl = this.decayHalfLifeSeconds;
    if (hl <= 0 || fact.epistemicClass === 'axiom') return fact.confidence;
    const ageSec = Math.max(0, now - fact.validFrom) / 1000;
    return fact.confidence * Math.exp(-Math.log(2) * ageSec / hl);
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

    // One-time cleanup: collapse duplicate immutable axioms that legacy
    // (non-idempotent) ingestion stacked. Axioms are immutable and identical,
    // so keeping the earliest row per identity is always correct. The FTS
    // index stays consistent via the AFTER DELETE trigger.
    this.db.exec(`
      DELETE FROM facts
      WHERE epistemic_class = 'axiom' AND status = 'active'
        AND rowid NOT IN (
          SELECT MIN(rowid) FROM facts
          WHERE epistemic_class = 'axiom' AND status = 'active'
          GROUP BY subject, predicate, object, scope_id
        );
    `);
    } catch {
      // Ignore migration errors on fresh tables
    }
  }

  /**
   * Store a fact using AGM-compliant bitemporal append with Epistemic Classes, Scopes and TTL.
   */
  async storeFact(fact: Omit<BitemporalFact, 'id' | 'txFrom' | 'txTo' | 'status' | 'validFrom' | 'validTo'> & { validFrom?: number; validTo?: number; ttlSeconds?: number }): Promise<BitemporalFact> {
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

    // Idempotency: an equivalent active fact (same identity + scope) already
    // exists -> return it instead of inserting a duplicate. This prevents the
    // static `config.facts` re-ingestion on every plugin (re)activation from
    // stacking identical axiom rows (e.g. 5x copies of each host fact).
    const duplicate = this.db.prepare(`
      SELECT * FROM facts
      WHERE subject = ? AND predicate = ? AND object = ? AND scope_id = ?
        AND status = 'active' AND valid_from <= ? AND valid_to > ?
    `).get(fact.subject, fact.predicate, fact.object, scopeId, now, now) as any;
    if (duplicate) {
      return {
        id: duplicate.id,
        ...fact,
        epistemicClass: duplicate.epistemic_class,
        scopeType: duplicate.scope_type,
        scopeId: duplicate.scope_id,
        author: duplicate.author,
        validFrom: duplicate.valid_from,
        validTo: duplicate.valid_to,
        txFrom: duplicate.tx_from,
        txTo: duplicate.tx_to,
        status: duplicate.status,
      };
    }

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

    const text = `${fact.subject} ${fact.predicate} ${fact.object}`;

    // Vector embedding (role 'passage'). Degrade gracefully: if the provider is
    // absent or unavailable (e.g. ONNX model missing), we store the fact without
    // an embedding and the retrieval cascade falls back to keyword recall.
    let embeddingBlob: Buffer | null = null;
    if (this.embeddingProvider) {
      try {
        embeddingBlob = floatToBlob(await this.embeddingProvider.embed(text, 'passage'));
      } catch (err) {
        if (!(err instanceof EmbeddingUnavailableError)) throw err;
        // provider configured but unusable -> keep fact, skip vector
      }
    }

    const ftsTokens = decomposeToStems(text).join(' ');

    const insertStmt = this.db.prepare(`
      INSERT INTO facts (
        id, subject, predicate, object, fts_tokens,
        valid_from, valid_to, tx_from, tx_to,
        type_constraint, confidence, security_label, status,
        scope_type, scope_id, author, epistemic_class, embedding_blob
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
      epistemicClass,
      embeddingBlob
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
  async recallContextGuarded(options: {
    queryText: string;
    identity?: { username: string; groups?: string[]; clearance?: string };
    repoId?: string;
    recentTurnTexts?: string[];
    maxTokens?: number;
    minThreshold?: number;
    /** Minimum substantive stems before a query triggers recall (default 1). */
    entropyMinStems?: number;
  }): Promise<BitemporalFact[]> {
    const {
      queryText,
      identity,
      repoId,
      recentTurnTexts = [],
      maxTokens = 150,
      minThreshold = -1.5, // in SQLite FTS5 bm25(), more negative = better match
      entropyMinStems = 1,
    } = options;

    // 1. Entropy Gate: Ignore short greetings, affirmative replies, or smalltalk.
    // A SINGLE substantive stem (e.g. an entity name like "strummer") is highly
    // informative and MUST trigger recall; only true trivial queries (all
    // stopwords / very short) are suppressed to zero tokens.
    const queryStems = decomposeToStems(queryText)
      .filter((w) => w.length > 2 && !STOPWORDS.has(w.toLowerCase()))
      .slice(0, 16);

    if (queryStems.length < entropyMinStems) {
      return [];
    }

    const recentHistoryFlat = recentTurnTexts.join(' ').toLowerCase();
    const now = Date.now();

    // Candidate pool keyed by fact identity -> { fact, bm25?, cosine? }.
    const pool = new Map<string, { fact: BitemporalFact; bm25?: number; cosine?: number }>();

    // --- Stage 1: BM25 keyword recall (strict, then looser fallback) ---
    const matchQuery = queryStems.map(t => `"${t}"*`).join(' OR ');
    const sql = `
      SELECT f.*, bm25(facts_fts) as score
      FROM facts f
      JOIN facts_fts ON f.id = facts_fts.id
      WHERE f.status = 'active'
        AND f.valid_from <= ? AND f.valid_to > ?
        AND f.tx_from <= ? AND f.tx_to > ?
        AND facts_fts MATCH ?
      ORDER BY score ASC
      LIMIT 30
    `;
    let bm25Rows: any[] = [];
    try {
      bm25Rows = this.db.prepare(sql).all(now, now, now, now, matchQuery) as any[];
    } catch {
      bm25Rows = [];
    }
    const pass = bm25Rows.some(r => r.score <= minThreshold) ? minThreshold : 0;
    const dedupKey = (s: string, p: string, o: string, sc: string) => `${s}\u0000${p}\u0000${o}\u0000${sc}`;
    for (const r of bm25Rows) {
      if (r.score > pass) continue; // below cutoff -> skip
      if (!this.visibleRow(r, identity, repoId)) continue;
      if (recentHistoryFlat.includes(r.subject.toLowerCase()) && recentHistoryFlat.includes(r.object.toLowerCase())) continue;
      if (!pool.has(dedupKey(r.subject, r.predicate, r.object, r.scope_id))) pool.set(dedupKey(r.subject, r.predicate, r.object, r.scope_id), { fact: this.rowToFact(r), bm25: bm25Norm(r.score) });
    }

    // --- Stage 2: vector (cosine) semantic recall (primary ranker) ---
    if (this.embeddingProvider) {
      try {
        const vecResults = await this.recallVector(queryText, identity, repoId);
        for (const { fact, similarity } of vecResults) {
          if (recentHistoryFlat.includes(fact.subject.toLowerCase()) && recentHistoryFlat.includes(fact.object.toLowerCase())) continue;
          const key = dedupKey(fact.subject, fact.predicate, fact.object, fact.scopeId);
          const existing = pool.get(key);
          if (existing) existing.cosine = Math.max(existing.cosine ?? 0, similarity);
          else pool.set(key, { fact, cosine: similarity });
        }
      } catch (err) {
        if (!(err instanceof EmbeddingUnavailableError)) throw err;
        // vector stage unavailable -> keep keyword recall
      }
    }

    // --- Fuse: weighted blend (embedding primary), deterministic tiebreak ---
    const candidates = Array.from(pool.values()).map(c => ({
      ...c,
      score: this.weight * (c.cosine ?? 0) + (1 - this.weight) * (c.bm25 ?? 0),
    }));
    candidates.sort((a, b) => {
      if (b.score !== a.score) return b.score - a.score;
      // deterministic tiebreak
      const ka = `${a.fact.scopeId}\u0000${a.fact.id ?? ''}`;
      const kb = `${b.fact.scopeId}\u0000${b.fact.id ?? ''}`;
      return ka < kb ? -1 : ka > kb ? 1 : 0;
    });

    const result: BitemporalFact[] = [];
    const seen = new Set<string>();
    let accumulatedTokens = 0;
    for (const c of candidates) {
      const key = dedupKey(c.fact.subject, c.fact.predicate, c.fact.object, c.fact.scopeId);
      if (seen.has(key)) continue;
      // A1 Decay: drop facts whose derived confidence fell below the floor.
      if (this.decayFloor >= 0 && this.effectiveConfidence(c.fact) < this.decayFloor) continue;
      const line = `- ${c.fact.subject} ${c.fact.predicate} ${c.fact.object} (${c.fact.scopeId})\n`;
      const estimatedTokens = Math.ceil(line.length / 4);
      if (accumulatedTokens + estimatedTokens > maxTokens) break; // Hard budget reached
      seen.add(key);
      result.push(c.fact);
      accumulatedTokens += estimatedTokens;
    }

    return result;
  }

  /**
   * Top-K nearest facts by cosine similarity against the query embedding.
   * Evaluates every active fact with a stored embedding (brute-force scan);
   * the fact population is tiny, so this is O(N·d) and effectively instant.
   * Permission/scope visibility is enforced per row.
   */
  async recallVector(
    queryText: string,
    identity?: { username: string; groups?: string[]; clearance?: string },
    repoId?: string,
  ): Promise<Array<{ fact: BitemporalFact; similarity: number }>> {
    if (!this.embeddingProvider) return [];
    const qv = await this.embeddingProvider.embed(queryText, 'query');
    if (!qv || qv.length === 0) return [];

    const now = Date.now();
    const rows = this.db.prepare(`
      SELECT id, subject, predicate, object, valid_from, valid_to, tx_from, tx_to,
        type_constraint, confidence, security_label, status, scope_type, scope_id,
        author, epistemic_class, embedding_blob
      FROM facts
      WHERE status = 'active'
        AND valid_from <= ? AND valid_to > ?
        AND tx_from <= ? AND tx_to > ?
        AND embedding_blob IS NOT NULL AND length(embedding_blob) > 0
    `).all(now, now, now, now) as any[];

    const scored: Array<{ fact: BitemporalFact; similarity: number }> = [];
    const seen = new Set<string>();
    for (const r of rows) {
      const v = blobToFloat(r.embedding_blob);
      if (!v) continue;
      if (!this.visibleRow(r, identity, repoId)) continue;
      const sim = cosine(qv, v);
      if (!Number.isFinite(sim)) continue;
      const key = `${r.subject}\u0000${r.predicate}\u0000${r.object}\u0000${r.scope_id}`;
      if (seen.has(key)) continue;
      seen.add(key);
      scored.push({ fact: this.rowToFact(r), similarity: Math.max(0, sim) });
    }

    // Rank by descending cosine, then apply a two-tier relevance floor so the
    // recall never injects semantically-weak tail facts:
    //   1. absolute floor (minSimilarity)
    //   2. relative margin to the best match (similarityMargin) — adaptive:
    //      always keeps the strongest result and trims the far tail, without
    //      needing a brittle, globally-tuned absolute threshold.
    scored.sort((a, b) => b.similarity - a.similarity);
    const best = scored.length > 0 ? scored[0].similarity : 0;
    const cutoff = Math.max(this.minSimilarity, best - this.similarityMargin);
    return scored.filter((s) => s.similarity >= cutoff).slice(0, this.vectorTopK);
  }

  /**
   * Backfill missing embeddings (first run after enabling the provider, or
   * after a model/dimension change) for facts with none. Runs once at startup;
   * failures for individual facts are non-fatal.
   */
  async backfillEmbeddings(): Promise<number> {
    if (!this.embeddingProvider) return 0;
    const rows = this.db.prepare(`
      SELECT id, subject, predicate, object FROM facts
      WHERE status = 'active' AND (embedding_blob IS NULL OR length(embedding_blob) = 0)
    `).all() as any[];
    let done = 0;
    for (const r of rows) {
      try {
        const vec = await this.embeddingProvider.embed(`${r.subject} ${r.predicate} ${r.object}`, 'passage');
        this.db.prepare(`UPDATE facts SET embedding_blob = ? WHERE id = ?`).run(floatToBlob(vec), r.id);
        done++;
      } catch {
        // non-fatal: keep keyword recall for this fact
      }
    }
    return done;
  }

  /** Map a raw facts row into a {@link BitemporalFact}. */
  private rowToFact(r: any): BitemporalFact {
    return {
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
      epistemicClass: r.epistemic_class,
    };
  }

  /** Lattice / multi-tenant visibility check for a single raw fact row. */
  private visibleRow(
    r: any,
    identity?: { username: string; groups?: string[]; clearance?: string },
    repoId?: string,
  ): boolean {
    // Water-tight default: an ABSENT identity is RESTRICTIVE (public-only), never
    // administrative. Wider access always requires an explicitly authenticated
    // tenant carrying the matching scope / clearance.
    if (!identity) return r.scope_type === 'public';
    if (identity.clearance === 'Admin') return true;
    if (r.scope_type === 'public') return true;
    if (r.scope_type === 'user') return r.scope_id === `user:${identity.username}`;
    if (r.scope_type === 'group') return identity.groups?.includes(r.scope_id.replace(/^group:/, '')) ?? false;
    if (r.scope_type === 'repo') return repoId ? r.scope_id === `repo:${repoId}` : false;
    return false;
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
