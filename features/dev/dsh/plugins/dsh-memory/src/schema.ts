import { DatabaseSync } from 'node:sqlite';
import * as fs from 'node:fs';
import * as path from 'node:path';

export function initializeDatabase(dbPath: string): DatabaseSync {
  if (dbPath !== ':memory:') {
    const dir = path.dirname(dbPath);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
    }
  }

  const db = new DatabaseSync(dbPath);

  // Enable WAL and foreign keys
  if (dbPath !== ':memory:') {
    db.exec('PRAGMA journal_mode = WAL;');
  }
  db.exec('PRAGMA foreign_keys = ON;');

  // Bitemporal Facts Schema (Oktatupel + Scopes + Author)
  db.exec(`
    CREATE TABLE IF NOT EXISTS facts (
      id TEXT PRIMARY KEY,
      subject TEXT NOT NULL,
      predicate TEXT NOT NULL,
      object TEXT NOT NULL,
      valid_from REAL NOT NULL,
      valid_to REAL NOT NULL,
      tx_from REAL NOT NULL,
      tx_to REAL NOT NULL,
      type_constraint TEXT NOT NULL DEFAULT 'String',
      confidence REAL NOT NULL DEFAULT 1.0,
      security_label TEXT NOT NULL DEFAULT 'system',
      status TEXT NOT NULL DEFAULT 'active',
      scope_type TEXT NOT NULL DEFAULT 'public',
      scope_id TEXT NOT NULL DEFAULT 'public',
      author TEXT NOT NULL DEFAULT 'system',
      embedding_blob BLOB
    );

    CREATE INDEX IF NOT EXISTS idx_facts_subject_predicate ON facts(subject, predicate);
    CREATE INDEX IF NOT EXISTS idx_facts_bitemporal ON facts(valid_from, valid_to, tx_from, tx_to);
    CREATE INDEX IF NOT EXISTS idx_facts_security ON facts(security_label);
    CREATE INDEX IF NOT EXISTS idx_facts_status ON facts(status);
    CREATE INDEX IF NOT EXISTS idx_facts_scope ON facts(scope_type, scope_id);
    CREATE INDEX IF NOT EXISTS idx_facts_author ON facts(author);

    -- SQLite FTS5 Fulltext Search Index
    CREATE VIRTUAL TABLE IF NOT EXISTS facts_fts USING fts5(
      id UNINDEXED,
      subject,
      predicate,
      object,
      tokenize = 'porter unicode61'
    );

    -- Sync triggers to keep FTS5 index consistent
    CREATE TRIGGER IF NOT EXISTS trg_facts_ai AFTER INSERT ON facts BEGIN
      INSERT INTO facts_fts(id, subject, predicate, object)
      VALUES (new.id, new.subject, new.predicate, new.object);
    END;

    CREATE TRIGGER IF NOT EXISTS trg_facts_ad AFTER DELETE ON facts BEGIN
      DELETE FROM facts_fts WHERE id = old.id;
    END;

    CREATE TRIGGER IF NOT EXISTS trg_facts_au AFTER UPDATE ON facts BEGIN
      DELETE FROM facts_fts WHERE id = old.id;
      INSERT INTO facts_fts(id, subject, predicate, object)
      VALUES (new.id, new.subject, new.predicate, new.object);
    END;
  `);

  return db;
}
