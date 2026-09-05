/**
 * @module @dsh/memory/types
 * Formal types for Bitemporal Knowledge Representation, Lattice Security, and Datalog Inferences.
 */

export type SecurityLabel = 'system' | 'operator' | 'user';

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
  semanticSearch?: {
    queryEmbedding: number[];
    limit?: number;
  };
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
}

export interface QueryMemoryArgs {
  subject?: string;
  predicate?: string;
  as_of_time?: number;
  recursive_closure?: boolean;
}
