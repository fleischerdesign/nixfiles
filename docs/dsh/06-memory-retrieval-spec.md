# Formale Spezifikation: Wasser-dichtes Memory-Retrieval (`dsh-memory`)

**Status:** Entwurf (implementiert in diesem Arbeitsgang)
**Scope:** Retrieval-Kaskade BM25 + semantische Embeddings (API-Provider), Multi-Tenant-Lattice, Bitemporal-Validität, Token-Budget, Skalierung.
**Bezüge:** [`05-memory-reliability-and-edge-cases.md`](05-memory-reliability-and-edge-cases.md), [`memory-architecture.md`](../../features/dev/dsh/docs/memory-architecture.md)

Diese Spezifikation definiert den exakten Vertrag des Agenten-Gedächtnis-Retrievals. Ziel ist ein **wasser-dichtes** System: korrekt, leak-frei, budgetiert, deterministisch, degradierungssicher und skalierend — ohne hartkodierte Domänenheuristiken (ausdrücklich **kein** Synonym-Wörterbuch).

---

## 1. Vertrag (Invarianten)

Für jede Anfrage `(Q, T)` mit Tenant `T = ⟨username, groups[], clearance⟩` muss die Kaskade deterministisch liefern:

| ID | Invariante |
|---|---|
| **I1 Korrektheit** | Nur faktisch sichtbare Fakten (Lattice `security_label` + `scope`), nur bitemporal gültige. |
| **I2 Leak-Freiheit** | Keine Kreuz-Tenant-Injektion; nie mehr als die Scopes, die `T` besitzt. Eine fehlende Identität ist **restriktiv** (nur `public`), nie Administrator. |
| **I3 Token-Garantie** | Hartes Budget `maxTokens`; triviale Queries ⇒ exakt **0** zusätzliche Tokens. |
| **I4 Determinismus** | Gleiche DB + `Q` + `T` ⇒ identische Ausgabe (stabile Sortierung mit explizitem Tiebreak). |
| **I5 Degradation** | Ausfall/Timeout der Embedding-Stufe fällt auf BM25 zurück; nie ein Crash, nie ein leerer Recall bei vorhandenen Fakten. |
| **I6 Agnostisch** | Kein domänenspezifisches Wissen (kein Wörterbuch, keine Regeln über Host-/Service-Namen). |

---

## 2. Architektur (Schichten)

```
┌─ 1 Normalisierung (text.ts) ─ decomposeToStems, Stopwörter, feature-hash, normalize, cosine
├─ 2 Embedding-Provider (embedding.ts) ─ EmbeddingProvider-Seam
│     ├─ ApiEmbeddingProvider      (OpenAI-kompatibel /v1/embeddings; Modell via Nix)
│     └─ OnnxEmbeddingProvider     (lokal, optional; Offline-Stufe)
├─ 3 Persistenz (engine.ts) ─ embedding_blob + Embedding-Signatur (provider+dims), Backfill
├─ 4 Retrieval-Kaskade (engine.ts) ─ Entropy-Gate → {BM25 ∥ Embedding-Cosine} → Fuse → Guards
└─ 5 Injektion (index.ts) ─ formatierte, budgetierte prompt-Sektion
```

---

## 3. Retrieval-Pipeline (Stufe für Stufe, mit Guards)

### 3.1 Normalisierung
Query wird in inhaltstragende Stämme zerlegt (CamelCase, Namespace-Delimiter, Wortstämme), Stopwörter entfernt.

### 3.2 Entropy-Gate (I3)
**Neu:** substanziell ⇔ es existiert **≥1** inhaltstragender Stamm (Länge ≥3, kein Stopwort).
- `"ok"`, `"danke"`, `"wie"` → 0 Stämme ⇒ **kein Recall** (0 Tokens, 0 API-Call, keine Suche).
- `"strummer"`, `"ip"` → 1 Stamm ⇒ **Recall** (einzelnes Entity ist hochinformativ, kein Smalltalk).
- Konfigurierbar `entropyMinStems` (Default 1).

*Begründung:* Der frühere Schwellwert `<2 Stämme` erzeugte Falsch-Negative auf einzelne Entitäten.

### 3.3 Kandidatenerzeugung (parallele Stufen)
Beide Stufen laufen, werden aber unabhängig validiert und fusioniert:

- **BM25-Stufe (offline, exakt):** FTS5 `bm25`-Suche. Filtert: `status='active'`, **`valid_from <= now < valid_to`**, **`tx_from <= now < tx_to`**, Scope-Lattice.
- **Embedding-Stufe (primär, semantisch):** Query-Embedding via Provider, Cosine-Top-K über gespeicherte Vektoren. Filtert: Bitemporal-Validität, `scope`-Lattice, `minSimilarity`, `topK`.

### 3.4 Fusion & Rang
- **Embedding ist der primäre Ranker** (semantisch genauer, I6).
- BM25 dient als **Supplement** (exakte Token-/Entity-Matches, die Cosine unterschätzt) und als **Offline-Fallback**.
- Kombinierter Score = `w·cosine_norm + (1−w)·bm25_norm` mit Default `w = 0.7`, deterministischer Tiebreak (`scope_id`, dann `id`).

### 3.5 Guards (I1–I4)
1. **Bitemporal-Validität** (alle vier Grenzen) — inhärent in beiden Stufen UND in der Fusion.
2. **Scope-Lattice**: `visibleRow(T)` — `public` immer; `user` nur `user:<T>`; `group` nur bei Gruppenmitgliedschaft; `repo` nur bei passender `repoId`. **Fehlende Identität ⇒ nur `public`.**
3. **Dedup-Schlüssel** = `subject|predicate|object|scope_id` (nicht nur Triple — verhindert Kollaps scope-verschiedener Fakten).
4. **Token-Budget**: `maxTokens` (Default 150) hart begrenzt.

### 3.6 Injektion
Formatierte, budgetierte Sektion `[Recalled Knowledge Memories]:` mit `subject predicate object [epistemicClass] (scopeId)`. Lossless-Text, keine Control-Injection.

---

## 4. Fehler- und Edge-Case-Matrix

| Szenario | Detektion | Verhalten (wasser-dicht) |
|---|---|---|
| Triviale Query | Entropy-Gate | **0 Tokens**, kein API-Call |
| Einzel-Entity-Query ("strummer") | ≥1 Stamm | Recall läuft |
| Abgelaufener Fakt | Bitemporal-Filter | nicht injiziert |
| Fakt ohne Embedding | `embedding_blob NULL` | Vector-Stufe überspringt ihn, BM25 greift |
| Provider/Dims-Wechsel | Embedding-Signatur (provider+dims) | gezielter Re-Backfill, keine Dimension-Mismatch |
| NaN-/Leer-Vektor | `normalize`/`cosine` Guards | wird verworfen (kein Score, kein Crash) |
| Gleiche Scores | deterministischer Tiebreak | stabile Reihenfolge |
| API down/timeout | try/catch + Timeout | Vector-Stufe aus, **BM25-Offline-Fallback** |
| Modell fehlt (ONNX) | `EmbeddingUnavailableError` | BM25-Fallback |
| Identität fehlt | `visibleRow` | **nur `public`** (restriktiv, kein Admin) |
| DB-Lock/Fehler | try/catch | leerer Recall, kein Crash |
| Konkurrenz | WAL + transaktional pro Fakt | konsistente Snapshots |

---

## 5. Security (Multi-Tenant Lattice)

- `security_label ∈ {system<user<operator}` — eine Anfrage sieht nur `≤ clearance`.
- → `scope_type ∈ {public, group, user, repo}` — strikte Mitgliedschaftsprüfung.
- **Standard-Restriktion:** Unauthentiziert ⇒ `public`-only. `Admin` nur bei explizit verifiziertem Loopback/Tenant (Nix-Konfig `loopbackClearance`), nie als Default bei fehlender Identität.

---

## 6. Skalierung

**Brute-Force-Cosine ist O(N·d) und skaliert nicht für "viele Fakten".**

| N (sichtbare Fakten pro Tenant) | Ansatz | Latenz |
|---|---|---|
| ≤ ~5 000 | Brute-Force-Cosine (O(N·d)) | µs–ms |
| darüber | **ANN-Index** (HNSW / `sqlite-vec`) | ~ms, unabhängig von N |

**Implementation:**
- `VectorIndex`-Seam mit `LinearVectorIndex` (Default, korrekt, klein) und `AnnVectorIndex` (bei Überschreitung `annThreshold`).
- **Tenant-scoped Kandidaten-Vorfilter** reduziert N pro Query auf die sichtbare Facette (Multi-Tenant-Skalierung).

---

## 7. Provider-Entscheidung: Embedding-API + BM25

- **DeepSeek**: kein Embeddings-Endpoint (anfragt, [Issue #1124](https://github.com/deepseek-ai/DeepSeek-V3/issues/1124#1), [Issue #802](https://github.com/deepseek-ai/DeepSeek-R1/issues/802#1)) ⇒ **nicht** fürs Embeding.
- **OpenRouter** (bereits konfiguriert): OpenAI-kompatibles `/v1/embeddings`, Modelle `openai/text-embedding-3-small` (Default), `-large`, `qwen/qwen3-embedding-8b`.
- **Kosten:** ~$0.02/1M Tokens (`-small`); bei 1 Query/Turn + Batch-Ingestion ≈ **Cents-Bereich/Tag**. Dominante Kosten bleiben die LLM-Turns.
- **Latenz:** ~50–150 ms/Query-Embedding, **parallel** zur BM25-Suche, entropy-gated (nur substanzielle Queries), <5 % der Turn-Latenz.
- **Graceful degradation:** API-Ausfall ⇒ BM25 offline.

---

## 8. Nix-Config-Surface

```nix
my.features.dev.dsh.memory.embedding = {
  enable = true;
  provider = "api";            # api | onnx (Offline-Stufe)
  apiBase   = null;            # default: OpenRouter base
  apiModel  = "openai/text-embedding-3-small";
  apiKeyEnv = "OPENROUTER_API_KEY";   # aus dsh-credentials
  dims      = 1536;
  batchSize = 16;
  topK      = 8;
  minSimilarity = 0.0;
  maxTokens = 150;             # Token-Budget f. Injektion
  entropyMinStems = 1;
  weight    = 0.7;             # w in Score-Blend
  index     = "linear";        # linear | ann
  annThreshold = 5000;
  cacheQueryEmbeddings = true;
};
```

---

## 9. Verifizierbarkeit

- `tsc --noEmit` / `esbuild`: 0 Fehler.
- **Eigenschaftstests** (replay-deterministisch): identische DB+Q+T ⇒ identisches Ergebnis; Trivial-Query ⇒ 0 Tokens; Leak-Negativ (Fremd-tenant-Fakt nie injiziert); Bitemporal-Ablauf ⇒ nicht injiziert; API-down ⇒ BM25-Resultat.
- **Latenz-Benchmark** auf Host: Query-Embedding + Full-Kaskade (Ziel < 50 ms Overhead bei N≤5 000).
