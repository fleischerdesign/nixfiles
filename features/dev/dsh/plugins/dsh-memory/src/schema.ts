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

  // Bitemporal Facts Schema (Oktatupel)
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
      embedding_blob BLOB
    );

    CREATE INDEX IF NOT EXISTS idx_facts_subject_predicate ON facts(subject, predicate);
    CREATE INDEX IF NOT EXISTS idx_facts_bitemporal ON facts(valid_from, valid_to, tx_from, tx_to);
    CREATE INDEX IF NOT EXISTS idx_facts_security ON facts(security_label);
    CREATE INDEX IF NOT EXISTS idx_facts_status ON facts(status);
  `);

  return db;
}
