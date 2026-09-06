/**
 * @module @dsh/memory/text
 * Deterministic text-normalisation and vector primitives.
 *
 * Everything here is pure and side-effect free: identical input always yields
 * identical output. This is the foundation for the always-available local
 * embedding baseline and for the retrieval-cascade scoring.
 */

export const STOPWORDS = new Set([
  'the', 'is', 'at', 'which', 'on', 'and', 'a', 'an', 'in', 'that', 'to', 'for', 'it', 'with', 'as',
  'der', 'die', 'das', 'und', 'ist', 'in', 'den', 'von', 'zu', 'mit', 'auf', 'für', 'eine', 'einen', 'ein',
  'hallo', 'moin', 'hi', 'danke', 'bitte', 'ok', 'okay', 'yes', 'no', 'ja', 'nein', 'wie', 'was',
]);

/**
 * Pure morphological decomposition and sub-word indexing.
 * Decomposes CamelCase, namespace delimiters (: _ . - /), and common grammatical
 * affixes without relying on external heavy language runtimes.
 */
export function decomposeToStems(str: string): string[] {
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

/**
 * 32-bit non-cryptographic string hash (FNV-1a). Deterministic across runs.
 */
export function hashString(s: string): number {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return h >>> 0;
}

/**
 * L2-normalise a vector to a unit vector. Returns a new vector; a zero or
 * NaN-tainted input degrades to a well-defined all-zero vector (never NaN).
 */
export function normalize(v: Float32Array): Float32Array {
  let sum = 0;
  for (const x of v) sum += x * x;
  const norm = Math.sqrt(sum);
  const out = new Float32Array(v.length);
  if (!norm || !Number.isFinite(norm)) return out;
  for (let i = 0; i < v.length; i++) out[i] = v[i] / norm;
  return out;
}

/**
 * Cosine similarity between two equal-length vectors. Returns a number in
 * [-1, 1] (0 when a length is empty or zero). Never throws, never returns NaN.
 */
export function cosine(a: Float32Array, b: Float32Array): number {
  const L = Math.min(a.length, b.length);
  if (L === 0) return 0;
  let dot = 0;
  let na = 0;
  let nb = 0;
  for (let i = 0; i < L; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  const denom = Math.sqrt(na) * Math.sqrt(nb);
  if (!denom || !Number.isFinite(denom)) return 0;
  return dot / denom;
}

/**
 * Serialise a Float32Array to a byte Buffer for BLOB persistence (native
 * little-endian byte order, as produced by the SQLite BLOB round-trip).
 */
export function floatToBlob(v: Float32Array): Buffer {
  return Buffer.from(v.buffer, v.byteOffset, v.byteLength);
}

/**
 * Deserialise a BLOB byte Buffer back into a Float32Array (view over a copy so
 * the returned array is independently owned and safe to mutate).
 */
export function blobToFloat(b: Buffer | Uint8Array | null | undefined): Float32Array | null {
  if (!b || b.byteLength === 0) return null;
  const buf = Buffer.isBuffer(b) ? b : Buffer.from(b);
  const arr = new Float32Array(buf.length / 4);
  for (let i = 0; i < arr.length; i++) arr[i] = buf.readFloatLE(i * 4);
  return arr;
}
