/**
 * @module @dsh/memory/types
 * Formal types for Bitemporal Knowledge Representation, Epistemic Classes, Lattice Security, and Datalog Inferences.
 */

export type SecurityLabel = 'system' | 'operator' | 'user';
export type MemoryScopeType = 'public' | 'group' | 'user' | 'repo';
export type EpistemicClass = 'axiom' | 'evidence' | 'hypothesis';

export interface BitemporalFact {
  id?: string;
  subject: string;
  predicate: string;
  object: string;
  validFrom: number;
  validTo: number;
  txFrom: number;
  txTo: number;
  typeConstraint: string;
  confidence: number;
  securityLabel: SecurityLabel;
  status: 'active' | 'disputed' | 'retracted';
  scopeType: MemoryScopeType;
  scopeId: string; // 'public', 'group:dev', 'user:philipp', 'repo:nixfiles'
  author: string;
  epistemicClass?: EpistemicClass;
  embedding?: number[];
}

export interface FactQueryFilter {
  subject?: string;
  predicate?: string;
  object?: string;
  asOfValid?: number;
  asOfTx?: number;
  maxSecurityLabel?: SecurityLabel;
  minConfidence?: number;
  scopeType?: MemoryScopeType;
  scopeId?: string;
  epistemicClass?: EpistemicClass;
  search?: string; // FTS5 fulltext search query
}

export interface DatalogInferenceResult {
  facts: BitemporalFact[];
  derivedRelations: Array<{
    subject: string;
    predicate: string;
    object: string;
    depth: number;
  }>;
}

export interface StoreFactArgs {
  subject: string;
  predicate: string;
  object: string;
  type_constraint?: string;
  confidence?: number;
  security_label?: SecurityLabel;
  valid_from?: number;
  valid_to?: number;
  ttl_seconds?: number;
  scope_type?: MemoryScopeType;
  scope_id?: string;
  author?: string;
  epistemic_class?: EpistemicClass;
}

export interface QueryMemoryArgs {
  subject?: string;
  predicate?: string;
  as_of_time?: number;
  recursive_closure?: boolean;
}

export interface StaticFactDeclaration {
  subject: string;
  predicate: string;
  object: string;
  type_constraint?: string;
  confidence?: number;
  security_label?: SecurityLabel;
  scope_type?: MemoryScopeType;
  scope_id?: string;
  valid_to?: number;
}

export interface MemoryPluginConfig {
  dbPath?: string;
  facts?: StaticFactDeclaration[];
  factsFile?: string;
  autoConsolidate?: boolean; // Automatic turn-stopping memory consolidation
  maxRecallTokens?: number;
  minRecallThreshold?: number;
}
