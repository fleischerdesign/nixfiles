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
  /**
   * Optional vector-embedding configuration. When present, the plugin embeds
   * facts into `embedding_blob` and augments the recall cascade with cosine
   * similarity. Absent -> keyword (BM25) recall only.
   */
  embedding?: {
    /** Backend: 'feature-hash' (local, deterministic), 'api' (OpenAI-compatible endpoint), or 'onnx' (local neural). */
    provider?: 'feature-hash' | 'api' | 'onnx';
    /** Dimensionality (feature-hash baseline; api dims; onnx uses model dims unless overridden). */
    dim?: number;
    /** Local directory containing the ONNX model + tokenizer (onnx). */
    modelDir?: string;
    /** HF model id resolved by transformers.js (onnx). */
    modelId?: string;
    /** OpenAI-compatible base URL for /v1/embeddings (api). */
    apiBase?: string;
    /** Embedding model identifier (api). */
    apiModel?: string;
    /** Environment variable holding the API key (api). */
    apiKeyEnv?: string;
    /** Max inputs per batched request (api). */
    batchSize?: number;
    /** Cosine floor; candidates below this are discarded. */
    minSimilarity?: number;
    /** Relative margin to the best cosine; weaker facts further than this are discarded (default 0.2). */
    similarityMargin?: number;
    /** Number of vector candidates per recall (default 8). */
    topK?: number;
    /** Token budget for the injected memory section (default 150). */
    maxTokens?: number;
    /** Blend weight for cosine vs BM25 in the fused score (0..1). */
    weight?: number;
    /** Minimum substantive stems for a query to trigger recall (default 1). */
    entropyMinStems?: number;
  };

  /**
   * Optional cross-node memory replication (C7). When enabled, the plugin
   * serves a HMAC-signed `/mesh/memory/sync` endpoint and pulls deltas from
   * peer nodes, merging immutable versions as a CvRDT union (idempotent).
   */
  replication?: {
    enabled?: boolean;
    /** Local nodeId (authoritative origin for this node's facts). */
    nodeId?: string;
    /** HMAC secret; resolved from `secretEnv` or the dsh credential store. */
    secretEnv?: string;
    /** Tenant replication context: "user:<u>" or "group:<g>". Defaults to "user:local". */
    tenantContext?: string;
    /** Scopes this node is willing to replicate (public, group:<g>, user:<u>). Derived per-peer from presence. */
    scopes?: string[];
    /** Peers to pull from / serve to. `endpoint` is "host:port" or URL. */
    peers?: Array<{
      nodeId: string;
      endpoint: string;
      direction?: 'pull' | 'push' | 'bidirectional';
      /** Scope ids to replicate (e.g. "public", "group:dev", "user:philipp"). Default ["public"]. */
      scopes?: string[];
    }>;
    /** Bind a local HTTP endpoint for peers to pull from this node. */
    listenPort?: number;
    listenHost?: string;
    /** Pull cadence in ms (default 30_000). */
    syncIntervalMs?: number;
    /** Max versions per delta response (default 512). */
    maxVersionsPerSync?: number;
  };

  /**
   * Optional memory decay governance (A1). Decay is DERIVED, not stored: the
   * effective confidence is a pure function of base confidence + age, so it
   * stays convergent across nodes without replicating a mutating state.
   */
  decay?: {
    /** Half-life in seconds for evidence/hypothesis; 0 or undefined disables decay. */
    halfLifeSeconds?: number;
    /** Below this effective confidence a fact is dropped from recall (opt-in). */
    floor?: number;
    /** Physical pruning: retain retracted/historical versions for this many seconds before deletion (0 = keep all history). */
    retentionSeconds?: number;
    /** Run the physical compaction (VACUUM) every this many seconds (0 = disabled). */
    vacuumIntervalSeconds?: number;
  };
}
