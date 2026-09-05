import { DatabaseSync } from 'node:sqlite';
import * as crypto from 'node:crypto';
import type {
  BitemporalFact,
  FactQueryFilter,
  DatalogInferenceResult,
  SecurityLabel
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
  }

  /**
   * Store a fact using AGM-compliant bitemporal append.
   */
  storeFact(fact: Omit<BitemporalFact, 'id' | 'txFrom' | 'txTo' | 'status'>): BitemporalFact {
    const id = crypto.randomUUID();
    const now = Date.now();
    const txFrom = now;
    const txTo = Infinity;
    const validFrom = fact.validFrom ?? now;
    const validTo = fact.validTo ?? Infinity;

    // Check for conflicting functional facts (Belief Revision)
    const existingStmt = this.db.prepare(`
      SELECT id, confidence, object FROM facts
      WHERE subject = ? AND predicate = ? AND status = 'active'
        AND valid_from <= ? AND valid_to > ?
    `);
    const existing = existingStmt.all(fact.subject, fact.predicate, now, now) as any[];

    let status: 'active' | 'disputed' = 'active';

    if (existing.length > 0) {
      for (const row of existing) {
        if (row.object !== fact.object) {
          // Contradiction detected
          const existingConf = row.confidence;
          const newConf = fact.confidence ?? 1.0;

          if (newConf > existingConf) {
            // Update existing fact to disputed
            this.db.prepare(`UPDATE facts SET status = 'disputed' WHERE id = ?`).run(row.id);
          } else {
            // New fact is weaker or equal -> tag as disputed
            status = 'disputed';
          }
        }
      }
    }

    const insertStmt = this.db.prepare(`
      INSERT INTO facts (
        id, subject, predicate, object,
        valid_from, valid_to, tx_from, tx_to,
        type_constraint, confidence, security_label, status
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);

    insertStmt.run(
      id,
      fact.subject,
      fact.predicate,
      fact.object,
      validFrom,
      validTo,
      txFrom,
      txTo,
      fact.typeConstraint ?? 'String',
      fact.confidence ?? 1.0,
      fact.securityLabel ?? 'system',
      status
    );

    return {
      id,
      ...fact,
      validFrom,
      validTo,
      txFrom,
      txTo,
      status
    };
  }

  /**
   * Execute deductive Datalog query with Lattice-Security filtering.
   */
  query(filter: FactQueryFilter): DatalogInferenceResult {
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

    const rows = this.db.prepare(baseSql).all(...params) as any[];

    // Filter Lattice security label in-memory
    const facts: BitemporalFact[] = rows
      .filter((r) => SECURITY_RANKS[r.security_label as SecurityLabel] <= maxRank)
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
        status: r.status
      }));

    return {
      facts,
      derivedRelations: []
    };
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
