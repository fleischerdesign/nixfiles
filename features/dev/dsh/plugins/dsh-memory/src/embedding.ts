/**
 * @module @dsh/memory/embedding
 * Embedding layer: a pluggable {@link EmbeddingProvider} seam with two
 * implementations:
 *
 *  - {@link FeatureHashProvider}: fully local, deterministic feature-hash
 *    (bag-of-stems) vector. Zero dependencies, always available.
 *  - {@link OnnxEmbeddingProvider}: neural semantic embeddings via
 *    @huggingface/transformers (ONNX runtime), e.g. multilingual-e5-small,
 *    offering true cross-lingual/synonym similarity.
 *
 * Providers always emit L2-normalised unit vectors (see {@link normalize}), so
 * cosine ranking is stable and comparisons are meaningful. Load/init failures
 * are surfaced as {@link EmbeddingUnavailableError} so the retrieval cascade can
 * degrade gracefully to the keyword (BM25) stage.
 */

import { cosine, normalize, decomposeToStems, hashString } from './text.js';

/** Role of the text being embedded; meaningful for e5-style models. */
export type EmbeddingRole = 'query' | 'passage';

/** A semantic-ish embedding backend. */
export interface EmbeddingProvider {
  /** Stable backend identifier ('feature-hash' | 'onnx'). */
  readonly id: string;
  /** Dimensionality of the emitted vectors. */
  readonly dim: number;
  /**
   * Embed a single piece of text into an L2-normalised unit vector.
   * @throws {EmbeddingUnavailableError} when the backend cannot initialise.
   */
  embed(text: string, role?: EmbeddingRole): Promise<Float32Array>;
}

/** Raised when a provider is configured but cannot initialise (e.g. model
 * missing, native runtime absent, or an API call failed). The caller degrades
 * to the keyword (BM25) stage. */
export class EmbeddingUnavailableError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'EmbeddingUnavailableError';
  }
}

export interface EmbeddingProviderConfig {
  /** Backend: 'feature-hash' (baseline), 'api' (OpenAI-compatible endpoint), or 'onnx' (local neural). */
  provider: 'feature-hash' | 'api' | 'onnx';
  /** Dimensionality for the feature-hash baseline (ignored by api/onnx unless overriding). */
  dim?: number;
  /** Local directory containing the ONNX model + tokenizer (onnx only). */
  modelDir?: string;
  /** HF model id / local path resolved by transformers.js (onnx only). */
  modelId?: string;
  /** OpenAI-compatible base URL for /v1/embeddings (api only). Defaults to OpenRouter. */
  apiBase?: string;
  /** Embedding model identifier (api only). */
  apiModel?: string;
  /** Environment variable holding the API key (api only). */
  apiKeyEnv?: string;
  /** Optional key resolver (api only); when absent, falls back to process.env. */
  resolveKey?: (envName: string) => Promise<string | undefined>;
  /** Max inputs per batched request (api only). */
  batchSize?: number;
  /** Reject candidates below this cosine floor (0 = rely on topK). */
  minSimilarity?: number;
}

/**
 * Deterministic feature-hash (hashing trick) baseline embedding. Stems are
 * hashed into a fixed-dimension vector with signed TF weighting then L2
 * normalised. Fully local, deterministic, dependency-free.
 */
export class FeatureHashProvider implements EmbeddingProvider {
  readonly id = 'feature-hash';
  readonly dim: number;

  constructor(dim = 512) {
    this.dim = dim > 0 ? dim : 512;
  }

  async embed(text: string, _role: EmbeddingRole = 'query'): Promise<Float32Array> {
    const vec = new Float32Array(this.dim);
    for (const t of decomposeToStems(text)) {
      const h = hashString(t);
      const idx = h % this.dim;
      vec[idx] += (h & 1) === 0 ? 1 : -1;
    }
    return normalize(vec);
  }
}

/** Result shape returned by the transformers.js feature-extraction pipeline. */
interface FeatureExtractionOutput {
  data: Float32Array;
  dims: number[];
}

/**
 * Neural semantic embedding provider backed by @huggingface/transformers
 * (ONNX Runtime). Applies e5-style task prefixes ("query: " / "passage: "),
 * mean pooling and L2 normalisation. The model is loaded lazily on first use
 * and cached for the lifetime of the process.
 */
export class OnnxEmbeddingProvider implements EmbeddingProvider {
  readonly id = 'onnx';
  readonly dim: number;

  private extractor: { (text: string | string[], opts: Record<string, unknown>): Promise<FeatureExtractionOutput> } | null = null;
  private readonly modelId: string;
  private readonly modelDir?: string;

  constructor(opts: { modelId?: string; modelDir?: string; dim?: number }) {
    this.modelId = opts.modelId || 'intfloat/multilingual-e5-small';
    this.modelDir = opts.modelDir;
    // e5-small has 384-dim output; allow override but otherwise trust the model.
    this.dim = opts.dim || 384;
  }

  private async ensureLoaded(): Promise<void> {
    if (this.extractor) return;
    try {
      // Lazy import keeps the baseline usable even when the optional heavy
      // dependency is not installed.
      const { pipeline, env } = await import('@huggingface/transformers');
      if (this.modelDir) {
        // Point the HF cache at a local, immutable store directory so no
        // network access is needed at runtime.
        env.cacheDir = this.modelDir;
        env.allowRemoteModels = false;
        env.allowLocalModels = true;
      }
      const p = await pipeline('feature-extraction', this.modelId, {
        dtype: 'fp32',
        device: 'cpu',
      });
      // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment
      this.extractor = p as unknown as typeof this.extractor;
    } catch (err) {
      throw new EmbeddingUnavailableError(
        `ONNX embedding provider unavailable: ${(err as Error)?.message || String(err)}`,
      );
    }
  }

  async embed(text: string, role: EmbeddingRole = 'query'): Promise<Float32Array> {
    await this.ensureLoaded();
    const prefixed = role === 'passage' ? `passage: ${text}` : `query: ${text}`;
    const out = await this.extractor?.(prefixed, {
      pooling: 'mean',
      normalize: true,
      // do not pad/truncate: facts and queries are short
      padding: true,
    });
    if (!out || !out.data || out.data.length === 0) {
      throw new EmbeddingUnavailableError('ONNX embedder returned an empty vector.');
    }
    // e5 models emit 1 x tokens x dims; mean-pool collapses to a single vector.
    const vec = new Float32Array(out.data);
    return normalize(vec);
  }
}

/**
 * OpenAI-compatible remote embedding provider (e.g. via OpenRouter). Fully
 * agnostic & scalable: no fixed vocabulary, works with any fact/query content.
 * One network call per query (entropy-gated) and batched calls for fact
 * ingestion. Degrades to BM25 when the API is unavailable/timeout.
 */
export class ApiEmbeddingProvider implements EmbeddingProvider {
  readonly id = 'api';
  readonly dim: number;

  private readonly baseUrl: string;
  private readonly model: string;
  private readonly apiKeyEnv: string;
  private readonly resolveKey: (envName: string) => Promise<string | undefined>;
  private readonly batchSize: number;
  private readonly timeoutMs: number;

  constructor(opts: {
    apiBase?: string;
    apiModel?: string;
    apiKeyEnv?: string;
    dims?: number;
    batchSize?: number;
    timeoutMs?: number;
    resolveKey?: (envName: string) => Promise<string | undefined>;
  }) {
    this.baseUrl = (opts.apiBase || 'https://openrouter.ai/api/v1').replace(/\/$/, '');
    this.model = opts.apiModel || 'openai/text-embedding-3-small';
    this.apiKeyEnv = opts.apiKeyEnv || 'OPENROUTER_API_KEY';
    this.dim = opts.dims || 1536;
    this.batchSize = opts.batchSize || 16;
    this.timeoutMs = opts.timeoutMs || 10_000;
    // Default: resolve from the process environment. In dsh a resolver is wired
    // that uses the `credentials` service so the key is drawn from the encrypted
    // credential store rather than a raw env var.
    this.resolveKey = opts.resolveKey ?? (async (env: string) => process.env[env]);
  }

  private async request(inputs: string[]): Promise<Float32Array[]> {
    let apiKey: string | undefined;
    try {
      apiKey = await this.resolveKey(this.apiKeyEnv);
    } catch {
      apiKey = undefined;
    }
    if (!apiKey) {
      throw new EmbeddingUnavailableError(`Embedding API key for '${this.apiKeyEnv}' is not available.`);
    }
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const res = await fetch(`${this.baseUrl}/embeddings`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${apiKey}`,
        },
        body: JSON.stringify({ model: this.model, input: inputs }),
        signal: controller.signal,
      });
      if (!res.ok) {
        throw new EmbeddingUnavailableError(`Embedding API returned ${res.status} ${res.statusText}`);
      }
      const data = (await res.json()) as { data: Array<{ embedding: number[] }> };
      if (!Array.isArray(data.data) || data.data.length !== inputs.length) {
        throw new EmbeddingUnavailableError('Embedding API returned malformed payload.');
      }
      return data.data.map((d) => new Float32Array(d.embedding ?? []));
    } catch (err) {
      if (err instanceof EmbeddingUnavailableError) throw err;
      throw new EmbeddingUnavailableError(`Embedding API request failed: ${(err as Error)?.message || String(err)}`);
    } finally {
      clearTimeout(timer);
    }
  }

  async embed(text: string, _role: EmbeddingRole = 'query'): Promise<Float32Array> {
    const [vec] = await this.request([text]);
    if (!vec || vec.length === 0) throw new EmbeddingUnavailableError('Embedding API returned an empty vector.');
    return normalize(vec);
  }

  /** Batched embedding for fact ingestion (one request per batchSize). */
  async embedBatch(texts: string[]): Promise<Float32Array[]> {
    const out: Float32Array[] = [];
    for (let i = 0; i < texts.length; i += this.batchSize) {
      const chunk = texts.slice(i, i + this.batchSize);
      const vecs = await this.request(chunk);
      for (const v of vecs) out.push(normalize(v));
    }
    return out;
  }
}

/**
 * Build the configured provider. `feature-hash` is always constructible and
 * never throws. `api`/`onnx` initialise lazily — failures surface as
 * {@link EmbeddingUnavailableError} so the retrieval cascade can degrade to BM25.
 */
export function createEmbeddingProvider(config: Partial<EmbeddingProviderConfig> | undefined): EmbeddingProvider | undefined {
  if (!config) return undefined;
  if (config.provider === 'onnx') {
    return new OnnxEmbeddingProvider({
      modelId: config.modelId,
      modelDir: config.modelDir,
      dim: config.dim,
    });
  }
  if (config.provider === 'api') {
    return new ApiEmbeddingProvider({
      apiBase: config.apiBase,
      apiModel: config.apiModel,
      apiKeyEnv: config.apiKeyEnv,
      dims: config.dim,
      batchSize: config.batchSize,
      resolveKey: config.resolveKey,
    });
  }
  return new FeatureHashProvider(config.dim || 512);
}

export { cosine, normalize };
