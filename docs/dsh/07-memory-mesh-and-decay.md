# Cross-Node Memory Replication (C7) & Memory Decay Governance (A1)

**Status:** Spezifikation + **P1-Kern implementiert** — *revidiert gegen MTAA, Distributed-Mesh-Architektur & Formal Foundations*  
**Scope:** `dsh-memory` × `dsh-mesh` × `dsh-workspace-tx` (Node-lokal → cluster-weit, bitemporal, tenant-sicher)  
**Merge-/Autoritäts-Modell:** Replikation = **CvRDT G-Set/OR-Set-Union** (immutable, append-only); autoritäre Auflösung **query-time** via AGM-Belief-Revision (Confidence + Bayes-Decay), Ordnung `Axiom > Evidence > Hypothesis`.  
**Mesh-Auth:** **Biscuit/Datalog-Caveats** (Zero-Trust), ergänzt um HMAC nur als Fallback — *nicht* bare HMAC.

> **Implementierungsstand (P1):** Der Replikationskern liegt in
> `plugins/dsh-memory/src/replication.ts` (`MemoryReplicator`): Capability-token
> `sync`-Endpoint, HLC-Cursor-Pull, union-CRDT-Merge (`INSERT OR IGNORE` = idempotent),
> Scope-Filterung beider Seiten, `nextCursor` rückt hinter gefilterte Versionen vor.
> Verdrahtet in `index.ts` (fail-closed ohne Secret) und hinter
> `my.features.dev.dsh.memory.replication.*` deklarierbar. End-to-end isoliert
> getestet. P3+P0b (unten) sind umgesetzt.
>
> **A1-Implementierung:** `engine.effectiveConfidence()` (abgeleitet, nie gespeichert)
> mit exponentieller Halbwertszeit; Axiome nie abklingend; Decay-Floor-Filter im
> Recall; hinter `my.features.dev.dsh.memory.decay.*`. Isoliert verifiziert:
> Axiom=1.0 stabil, Evidence→0.5 nach einer Halbwertszeit, deaktiviert unverändert.
>
> **P3/HLC/Auth-Implementierung (vollständig):** `hlc.ts` (totale Ordnung
> `(ms,counter,nodeId)`), `capability.ts` (Zero-Trust-Capability-Tokens, Attenuation/
> Expiry/Nonce; Biscuit als WASM-Ziel), `schema.ts` (`tx_counter`/`tx_node`,
> `memory_tombstones`-OR-Set), `engine.ts` (HLC-Stempelung, `retractFact`→Tombstone,
> `applyTombstone` mit Axiom-Ausschluss), `replication.ts` (HLC-Cursor, Tombstone-Delta,
> Merge-Axiom-Immuntabilität, Capability+Body-HMAC-Auth). Isoliert verifiziert:
> Scope-Filter, Tombstone-Propagation (Empfänger markiert `retracted`), Axiom-Immuntabilität
> beim Merge, Capability-Verifikation/Attenuation.
>
> **Pruning + Per-Tenant (umgesetzt):** `replication.ts` `prune()` (Retention,
> incrementale VACUUM-Fenster, **Peer-Cursor-Sicherheit** — nie unter einen Peer-Cursor
> prunen) + `startPruneLoop()`; **Per-Tenant-Replikation** via `deriveContexts()` (aus
> lokaler Presence: je presentem User ein `user:<u>`-Kontext, plus geteilter
> public/group-Kontext; je Kontext eigener Sub/Scopes/Cursor/Root-Token) und
> **Group-Privacy-Fix** in `deriveScopes` (group:<g> nur wenn auch das LOKALE Node
> Mitglied ist — kein Group-Leak an Nicht-Mitglieder). Verifiziert: Pruning
> (Retention/Cursor/FTS), Per-Tenant (philipp↔alice je privates, nie das des anderen),
> Fremder bekommt nur public.

---

## 0. Abstrakt

`dsh-memory` hält derzeit einen **node-lokalen, bitemporalen Wissensgraphen** in SQLite.
`dsh-mesh` besitzt zwar das **Typgerüst** für Delta-Synchronisation
(`SyncDeltaRequest/Response` mit `facts: []`), liefert aber **keine** echten Fakten:
`/mesh/sync` antwortet hart mit `facts: []`, `/mesh/heartbeat` setzt `maxTx: Date.now()`
statt eines monotonen Transaktionszählers. **Cross-Node-Replikation existiert daher nicht —
sie ist ein leerer Stub.** Zudem existiert **kein geregeltes Vergessen**: Decay ist
architektonisch als Bayes-Term spezifiziert (`formal-foundations.md §4.2`), aber nicht
implementiert.

Dieses Dokument spezifiziert (i) ein **wasser-dichtes, tenant-gescopte, bitemporales
Replikationsprotokoll** für Facts über das Mesh, konsistent mit der etablierten
CvRDT-Architektur, und (ii) eine **deterministische Decay-Governance**, die Vergessen
konvergent und multi-tenant-sicher macht.

**Kerntheorem:** Decay wird als **abgeleitete** Funktion definiert, nicht als
gespeicherter Zustand. Damit bleibt die Replikation trivial-konvergent (Union immutabler
Versionen), und Pruning wird zur physischen, kommutativen Kompaktierung.

---

## 1. Motivations- & Lückenanalyse (evidenzbasiert)

Quellen: `plugins/dsh-memory/src/{engine,schema,index}.ts`, `plugins/dsh-mesh/src/{index,protocol,types}.ts`, `plugins/dsh-workspace-tx/src/types.ts`.

| # | Beobachtung | Datei:Zeile | Konsequenz |
|---|---|---|---|
| G1 | DB wird als **lokale Datei** geöffnet (`defaultDbPath`/`DSH_MEMORY_DB`); keinerlei `mesh`-Referenz ins Memory-Plugin. | `dsh-memory/src/index.ts:46` | Gedächtnis pro Host isoliert. |
| G2 | `/mesh/sync` gibt `facts: []` zurück. | `dsh-mesh/src/index.ts:497-505` | Kein Sender füllt, kein Empfänger merged. |
| G3 | `/mesh/heartbeat` liefert `maxTx: Date.now()` (kein echter Tx-Zähler). | `dsh-mesh/src/index.ts:474-480` | Cursor-Delta-Replikation unmöglich. |
| G4 | `/mesh/task`, `/mesh/stream/chunk`, `/mesh/sync` **ohne Authentisierung**. | `dsh-mesh/src/index.ts:506-540` | Cross-Node-Sync sonst beliebige Aktionen möglich. |
| G5 | Scope-Lattice + Bitemporal in `visibleRow()`/`query()` nur **lokal** wirksam. | `dsh-memory/src/engine.ts:612-628, 301-390` | Kein cluster-weiter Schutz vor Scope-Verletzung. |
| G6 | Axiom-Protection (`EpistemicProtectionViolation`) nur lokal. | `dsh-memory/src/engine.ts:188-190, 278-280` | Beim Merge könnte fremder Node Axiom überschreiben. |
| G7 | `confidence`/`valid_to`/`status` persistiert; kein aktives Decay. | `schema.ts:24-41`, `engine.ts:123-268` | Kein geregeltes Vergessen. |
| G8 | Scope-Typen divergieren: Memory `public/group/user/repo` vs. Workspace-Tx `user/group`. | `memory/src/types.ts:7`, `workspace-tx/src/types.ts:11` | Group-Workspace-Bezug nicht konsistent modelliert. |
| G9 | Architekturdoku spezifiziert **CozoDB/HNSW/LSM**; Implementierung = `node:sqlite`. | `docs/memory-architecture.md §5` vs. `engine.ts` | Divergenz: Modell ist Zielbild, Engine real SQLite. |

**Schlussfolgerung:** C7 ist **Neubau**. Jede Replikation muss das Lattice (G5),
Axiom-Immuntabilität (G6) und die **MTAA-Prozess-/Storage-Isolation** (`multi-tenancy.md §3`)
cluster-weit durchsetzen, sonst bricht sie die wasser-dichte Multi-Tenancy auf.

---

## 2. Formales Systemmodell

### 2.1 Entitäten

- **Node** `n ∈ N`, identifiziert durch `nodeId`.
- **Tenant** `t = (username, groups, clearance)` — authentisierte Identität.
- **Workspace** `w = canonicalWorkspaceUrn` — siehe `distributed-agent-mesh.md`; trägt `repo:*`-Scopes.
- **Fact-Version** `v` (Abschnitt 3.1) — immutable, append-only.
- **Replication-Pair** `(n_a, n_b)` — unidirektional, pro **Tenant-Kontext** abonniert.

### 2.2 Replikations-Semilattice (CvRDT) — *die etablierte Basis*

Per `memory-architecture.md §4.2` ist der Wissensgraph ein **Grow-Only Set (G-Set)**,
hinsichtlich Retract ein **Observed-Remove Set (OR-Set)**:

```
Kommutativität:  K_a ⊔ K_b = K_b ⊔ K_a
Assoziativität:  (K_a ⊔ K_b) ⊔ K_c = K_a ⊔ (K_b ⊔ K_c)
Idempotenz:      K ⊔ K = K
```

**Konvergenz-Garantie:** unabhängig von Reihenfolge, Wiederholung und Partial-Benachrichtigung
endet jeder Node in äquivalentem Zustand (Strong Eventual Consistency) — **ohne Distributed Locks**,
da Facts immutable sind. Daher ist **mindestens-einmal**-Wiederversand sicher; keine
Bestätigungs-Transaktion nötig.

### 2.3 Totale Ordnung (HLC statt Wanduhr)

Um kausale Ordnung bei Clock-Skew zu erhalten, trägt jede Version eine **Hybrid Logical Clock**:

```
T = (physicalMs, counter, nodeId)
```

Totalordnung lexikographisch über `(physicalMs, counter, nodeId)`. Fremdes `physicalMs`
wird beim Beobachten geklemmt (`local = max(local, observed)`), `counter` pro Node monoton.
Damit ist jede Version deterministisch total geordnet, **ohne** Annahme über Uhrensynchronität.

### 2.4 Konsistenzsemantik

- **Sichtbare Konsistenz:** eventual consistent, konvergent; keine Distributed-Transaction.
- **CAP-Wahl:** Partitionstoleranz + Verfügbarkeit (AP); Konvergenz bei Heilung.
- **Read-your-writes** nur node-lokal; fremde Nodes evtl. um ein Delta verzögert.
- **Beobachtungs-Atomarität:** pro Delta **eine** SQLite-WAL-Transaktion (alles-oder-nichts).

---

## 3. Domänenmodell

### 3.1 Fact-Version (immutable Oktatupel)

```
v = (
  id:        UUID,                       // physisch eindeutig, Ursprungs-Node
  subject, predicate, object: string,
  scope:     (scope_type, scope_id),     // public | group | user | repo
  security:  security_label,             // system | operator | user
  class:     axiom | evidence | hypothesis,
  confidence: number ∈ (0,1],
  author:    string,
  valid:     (valid_from, valid_to),     // valid_to=∞ möglich
  tx:        HLC,
  origin:    nodeId,
  status:    active | disputed | retracted | decayed,
  embedding: number[] | null
)
```

**Logischer Replikations-Schlüssel** (Register-Slot):

```
L = (subject, predicate, scope_type, scope_id)
```

`object` ist der Wert, der sich über `valid` ändern kann (Belief-Revision). **Alle**
Versionen eines `L` werden repliziert; der Empfänger ist-Union-merges sie (kein Verlust).

### 3.2 Group-Workspace-Integration (G8)

- Memory-`group:*` (z. B. `group:dev`) und Workspace-Tx-`group:*` (`workspace-tx/src/types.ts:47`)
  bezeichnen **denselben Gruppen-Namespace** → einheitliches `group:<name>`.
- Workspace-gebundene Fakten (`repo:*`, canonical `workspaceUrn`) bleiben **node-gebunden**:
  `repo:*` wird standardmäßig **nie** repliziert (Artefakt-Scope), nur per expliziter Whitelist.
- Ein **Group-Workspace** (mehrere Nodes, gemeinsame Gruppe) erhält einen impliziten
  `group:<name>`-Fact-Scope: alle Nodes dieser Gruppe serven/empfangen ihn nur für
  Gruppenmitglieder.

---

## 4. Sicherheitsmodell (Cross-Node)

### 4.1 Sichtbarkeits-Prädikat

Sei `canSee(t, v)` für Tenant `t` und Version `v`:

```
canSee(t, v) =
  v.scope_type = 'public'                                → true
  ∨ v.scope_type = 'group' ∧ v.scope_id ∈ t.groups       → true
  ∨ v.scope_type = 'user'  ∧ v.scope_id = t.username     → true
  ∨ t.clearance = 'Admin'                                 → true
  ∧ sonst false
```

### 4.2 Replikations-Richtlinie (opt-in, pro Tenant-Kontext)

```ts
replication: {
  enabled: boolean;
  auth: 'biscuit' | 'hmac-fallback';     // Biscuit ist Standard (formal-foundations §5)
  peers: Array<{
    nodeId: string;
    tenantContext: string;                // 'user:<u>' oder 'group:<g>' — Replikationsdomäne
    scopes: Array<'public' | { group: string } | { user: string }>;
    direction: 'pull' | 'push' | 'bidirectional';
  }>;
}
```

**Invarianten:**
- I-SEC1: Serving-Node filtert ausgehend mit `canSee(targetTenant, v)` **und** `v.scope ∈ scopes`.
- I-SEC2: Empfangs-Node validiert eingehend mit **seiner** `canSee(callerTenant, v)`; Verletzte verworfen + geloggt.
- I-SEC3: `repo:*` standardmäßig nie repliziert; nur explizit per Whitelist.
- I-SEC4: **MTAA-Isolation-Respekt:** Replikation läuft **nur** innerhalb des gleichen
  `tenantContext`. Facts dürfen die Tenant-Grenze **nicht** überschreiten — ein `user:philipp`-Fact
  auf Node A wird **nie** auf Node B eines anderen Tenants materialisiert. (`multi-tenancy.md §3`.)
- I-SEC5: Axiome nur akzeptiert, wenn `receiverOrigin = v.origin` oder Sender Admin → verhindert Fremd-Überschreibung.

### 4.3 Transport-Authentisierung (Biscuit, Zero-Trust)

Der bestehende `/mesh/*`-Handler ist unauth. Memory-Sync läuft auf einem **neuen, signierten**
Endpoint `/mesh/memory/sync` mit **Biscuit-Capability-Token** (formale Basis:
`formal-foundations.md §5`):

```datalog
check if time(now), now < <expiry>;          // zeitliche Frische
check if target_node("<receiver>");          // Host-Boundary
check if tenant(u), u == "<tenantContext>";  // Tenant-Caveat
check if scope(s), s ∈ <allowed_scopes>;     // Scope-Kapselung
check if operation_risk(R), R <= 1;          // keine R2 im Mesh ohne Zusatzschlüssel
```

Scheitert ein Caveat → Request an der Netzwerkschicht verworfen. HMAC dient nur als
lokaler Offline-Fallback (`auth: 'hmac-fallback'`), z. B. Loopback.

---

## 5. Sync-Protokoll

### 5.1 Cursor & Delta

Jeder Node hält pro (Peer, TenantContext) einen **Anwendungs-Cursor** = höchste angewendete HLC.

```
POST /mesh/memory/sync
{ fromNodeId, tenantContext, since: HLC, scopes: ScopeRef[] }

→ 200
{ fromNodeId, versions: Version[], nextCursor: HLC, complete: boolean }
```

`nextCursor` = höchste HLC in `versions` (sonst `since`). `complete=false` ⇒ Empfänger
fragt weiter (`since = nextCursor`), Pagination via `maxVersionsPerSync` (Standard 512).

### 5.2 Idempotenz & Partialfehler

Da Union-CRDT kommutativ/idempotent/assoziativ (2.2), ist Re-Send harmlos. `id`/`tx`
machen jede Version eindeutig; Duplikate werden am Register-Slot dedupliziert.

| Szenario | Verhalten | Garantie |
|---|---|---|
| Peer offline | Anfrage scheitert; Cursor bleibt; später Nachholeffekt. | Kein Verlust. |
| Antwort abgebrochen | Kein Teil-Apply (versions atomar committed). | Alles-oder-nichts pro Delta. |
| Cursor-Commit nach Crash | Re-Pull via `since=nextCursor`; Duplikate via Idempotenz verworfen. | Keine Lücke/Korruption. |
| Konfliktäre parallele Txs | Beide Versionen bleiben (Union); Auflösung query-time (Abschnitt 6). | Konvergent, keine Datenlöschung. |
| Cluster-Netzwerk A↔B↔C | Union je Node; Konvergenz bei Zusammenführung. | Eventuell-konsistent. |

---

## 6. Autoritäts-Auflösung (query-time, über der Union)

> **Wichtige Korrektur zur ersten Entwurfsfassung:** Die Union-Architektur (immutable,
> append-only, `memory-architecture.md §4.1`) erfordert **keine** destruktive
> Autoritäts-Abschattung beim Merge. Konfliktäre Versionen **koexistieren** (G-Set).
> Die Rangfolge steuert **welche** Versionssicht/Enable als aktiv ausgewertet wird
> (AGM-Belief-Revision, `formal-foundations.md §4`) — **nicht** welche physisch verworfen wird.

### 6.1 Surfacings-Rangfolge (abgestimmt `Axiom > Evidence > Hypothesis`)

```
rank: axiom=+2, evidence=+1, hypothesis=+0
authority(v) = ( rank(class(v)), confidence(v), tx(v) )
```

Beim **Auswerten** eines Register-Slots `L` mit koinzidenten (overlap valid, unterschiedlichem
`object`) Versionen:

1. **Axiom siegt über alles** (Rank + Überschuss → `status='active'`); konfliktäre
   evidence/hypothesis in gleicher Periode werden als `'disputed'` **ausgewertet**
   (Zeigt NICHT gelöscht; Historie intakt — `formal-foundations §4.2`).
2. **Axiom vs. Axiom, unterschiedl. object:** frühere (`tx`) bleibt aktiv; spätere wird
   `'disputed'`; echte Korrektur erfordert bewusste Retract+Re-Ingest (Admin).
3. **Evidence vs. Evidence:** höher `confidence` aktiv; Gleichstand → `tx`.
4. **Evidence vs. Hypothesis:** Evidence (Rank).
5. **Hypothesis vs. Hypothesis:** höher `confidence`, sonst `tx`.

### 6.2 Query-Integration der Autorität

`query()`/`recall*` rechnen die aktive Sicht **pro `L`** aus: die Rang-Aktive wird als
aktiv geführt, Verlierer als `'disputed'` (gleiche Sichtbarkeit-Relevanzfilter wie bisher,
`engine.ts`). Keine physische Mutation bei Query — damit deterministisch, kommutativ,
konvergent, und AGM-konform.

---

## 7. Decay-Governance (A1)

### 7.1 Abgeleitetes Decay (konvergent über Nodes)

Decay **mutiert keine replizierten Daten**. Der effektive Wert ist eine deterministische
Funktion von Basis + Bewertungszeitpunkt — exakt der Bayes-Term aus `formal-foundations §4.2`:

```
c_eff(v, τ) = w_src · c_model(v) · e^(−λ (τ − valid_from(v)))
   λ = ln(2) / halfLife
```

- **Axiom:** `λ = 0` (kein Decay; `halfLife = ∞`).
- **Evidence:** `confHalfLife` konfigurierbar (Standard `∞` = kein aktives Decay).
- **Hypothesis:** `halfLife` explizit; bei gesetztem `ttlSeconds` gilt die **harte**
  Gültigkeitsschranke und *kein* exponentielles Decay (Prioritätsregel).

### 7.2 Retrieval-Integration

`recallContextGuarded`/`recallVector`:
1. Basis-`confidence` aus DB.
2. `c_eff(v, now)` anwenden.
3. Relevanz-Filter `minConfidence` (bei Decay) **oder** Decay-Ratio-Floor `c_eff/confidence ≥ decayFloor`
   (verwirft stark veraltete Hypothesen, hält Axiome/Evidence stabil).

### 7.3 Materialisierung (optional, Effizienz)

Für sehr große Graphen wird `c_eff` periodisch in eine **nicht-replizierte** Cache-Spalte
materialisiert. Sie trägt keine logische Information → Replikation (nur Basisversionen) unberührt.

### 7.4 Pruning (physisch, kommutativ, nicht-repliziert)

```
1. DELETE FROM facts WHERE status='retracted' AND valid_to < now − retention
   (nur Versionen, deren Historie nicht mehr für Bitemporal-Rekonstruktion nötig)
2. FTS-Reindex für betroffene id
3. VACUUM / incremental_vacuum
```

- I-A1: Pruning löscht **nie** eine Version mit `valid_to=∞` (aktiv) oder `tx_to=∞`.
- I-A2: Pruning ist kommutativ und nicht-repliziert (nur physische Belege).
- I-A3: Pruning nie unter Peer-Cursor-Schwelle; `retention = max(retention_local, cursor[peer] − safetyWindow)`.

---

## 8. Edge-Case-Matrix

| # | Edge Case | Erwartung | Grund |
|---|---|---|---|
| E1 | Gleiches Fact zwei Nodes gleichzeitig | Ein aktives; Duplikat dedupliziert (Union dedup via `L`). | Idempotenz |
| E2 | Widersprüchliches Evidence Node B < Node A | Beide koexistieren; query-time höher `confidence` aktiv. | 6.1.3 |
| E3 | Node B versucht Axiom zu ändern | `EpistemicProtectionViolation` cluster-weit. | I-SEC5, G6 |
| E4 | Axiom vs. Axiom, anderes object | früheres aktiv, späteres `disputed`; Admin-Retract nötig. | 6.1.2 |
| E5 | Hypothese (`ttlSeconds`) läuft vor Sync ab | Peer wendet Version an; `c_eff=0` nach Ablauf → nicht relevant. | 7.1 |
| E6 | Empfangs-Lattice lehnt ab | verworfen + geloggt; kein Anwenden. | I-SEC2 |
| E7 | Peer offline → Nachholen | Cursor bleibt; nächster Sync holt nach. | 5.2 |
| E8 | Antwort bricht ab | Alles-oder-nichts pro Delta. | 5.2 |
| E9 | Konträre `valid`-Bereiche in Historie | koexistieren; query-time Auflösung; keine Löschung. | 6 |
| E10 | `repo:*` will auf fremden Node | blockiert (default); nur Whitelist. | I-SEC3 |
| E11 | Geldfälschtes Biscuit/HMAC | Request verworfen; Rate-Limit + Log. | 4.3 |
| E12 | Replay-Angriff | Frische-Caveat (now < expiry) + nonce. | 4.3 |
| E13 | Pruning vs. Peer-Cursor | `retention = max(lokal, cursor−Δ)`. | I-A3 |
| E14 | Node-Uhr falsch | HLC-Klemmung, Ordnung unabhängig von Wanduhr. | 2.3 |
| E15 | ≥10⁵ Versionen | Pagination; Vektor-Recall via `topK`+Decay-Floor. | 5.1, 7.2 |
| E16 | Zwei Tenants sehen denselben `public`-Fact | beide dürfen serven/empfangen; `canSee` public→true. | 4.1 |
| E17 | **Group-Workspace-Fact über Nodes** | nur Nodes mit `group`-Mitgliedschaft; `group:*` geclot. | 4.2, 3.2 |
| E18 | **Tenant-Grenzverletzung bei Replik** | verboten (I-SEC4); `user:u` bleibt node-gebunden. | 4.2 |

---

## 9. Szenario-Walkthroughs

### S1: Public-Fact wandert übers Cluster
`jello` speichert `(strummer, hasType, server)|public` (axiom, HLC T1). `mackaye` pullt
(scope public, biscuit). `canSee(philipp, v1)=true` → registriert. Recall auf `mackaye` findet es. ✓

### S2: Axiom-Korrektur
Fehlerhaftes Axiom nicht überschreibbar → `retract` (Origin/Admin) → Tombstone repliziert
(OR-Set remove). Neues korrektes Axiom mit späterem `valid_from` → alle Nodes sehen nur dieses. ✓

### S3: Node-Ausfall & Wiederkehr
`rollins` fällt aus, 500 neue Facts auf `jello`/`mackaye`. `rollins` holt via Cursor alle in
paginierten Deltas nach; Union-Merge konvergiert; keine Duplikate, kein Verlust. ✓

### S4: Hypothese läuft ab
`mackaye` speichert Hypothese `(svc, load, high)|group:dev` TTL=1h. Nach 90min `c_eff→0`,
Recall reagiert nicht. Pruning entfernt physisch nach `retention`, sobald kein Cursor drauf zeigt. ✓

### S5: Scope-Verletzung
`jello` (alice, dev) speichert privates `user:alice`. `mackaye` zieht `scopes:[{user:bob}]`.
`canSee(bob, user:alice)=false` → bleibt auf `jello`. ✓

### S6: Group-Workspace-Manövers (E17)
Nodes `mackaye`+`strummer`, Gruppe `dev`. Beide speichern `group:dev`-Facts. Nur Gruppenmitglieder
serven/empfangen sie; ein `user:bob`-Pull scheitert. ✓

---

## 10. Invarianten

| Id | Invariante | Beleg |
|---|---|---|
| I1 | **Convergence**: Union merge kommutativ/idempotent/assoziativ. | 2.2 |
| I2 | **No-unauthorized-scope**: `canSee` auf Empfängerseite. | 4.1, I-SEC2 |
| I3 | **Axiom-Immutability**: nie überschreibbar (lokal + cluster). | G6, 6.1.1, I-SEC5 |
| I4 | **Bitemporal-Integrity**: keine Löschung aktiver Historie; kein `valid_to<valid_from`. | 3.1, 6 |
| I5 | **Tombstone-Authority**: Retract reaktiviert keine jüngeren Versionen. | 4.1-SEC5, 6.2 |
| I6 | **Decay-serializability**: `c_eff` deterministische Funktion von Basis+τ. | 7.1 |
| I7 | **Prune-safety**: aktive/∞-Versionen nie gelöscht. | 7.4, I-A1 |
| I8 | **Privacy-by-default**: `repo:*` + private `user:*` nie ungefragt repliziert. | I-SEC3, I-SEC4 |
| I9 | **No-entropy-gate-bypass**: Recall-Relevanz erbt `entropyMinStems`. | engine.ts:424-430 |
| I10 | **Deterministic-tiebreak**: Gleichstand über (scopeId, id). | engine.ts:489-494 |
| I11 | **MTAA-Isolation**: Replikation überschreitet nie Tenant-Grenze. | I-SEC4, multi-tenancy §3 |
| I12 | **Zero-Trust-Mesh**: Biscuit-Caveat-Verifikation vor Anwendung. | 4.3, formal-foundations §5 |

---

## 11. Nix-Konfigurationsfläche

```nix
my.features.dev.dsh.memory = {
  enable = true;
  # … bestehend (embedding, etc.)
  replication = {
    enable = true;                # false (default): kein Cross-Node
    auth = "biscuit";             # oder "hmac-fallback"
    peers = [
      { nodeId = "jello";   tenantContext = "user:philipp"; scopes = ["public" { group = "dev";}]; direction = "bidirectional"; }
      { nodeId = "mackaye"; tenantContext = "user:philipp"; scopes = ["public" { user = "philipp";}]; direction = "pull"; }
    ];
  };
  decay = {
    enable = true;
    halfLifeSeconds = 7776000;    # 90 Tage (λ = ln2 / halfLife)
    confFloor = 0.15;
    retentionSeconds = 2592000;   # 30 Tage
    vacuumIntervalSeconds = 86400;
  };
};
```

Rendering via `lib/render.nix` → `pluginConfigs."dsh-memory".{replication,decay}`.
Biscuit-Key/`hmac`-Shared-Secret ausschließlich via `credentials.credentialRef` — **nie** in `settings.yaml`.

---

## 12. Observability

- Tool `memory_sync_stats`: pro (Peer, TenantContext) `{ applied, filteredByScope, rejectedByAuth, activeSurfacing, lastCursor, complete }`.
- Log `info` für Scope-Ablehnungen (I-SEC2), `debug` für Deltas.
- Client-Slot-Panel "Knowledge" zeigt pro injiziertem Fact `origin`-Node + Replikations-Peer.

---

## 13. Roadmap & Phasing

| Phase | Inhalt | Status |
|---|---|---|
| P0 | Mesh-Security: Capability-Token/Caveat auf `/mesh/memory/sync` (Capability-Auth); ungeschützten `/mesh/sync`-Stub unangetastet (kein Memory-Verkehr darauf). | ✅ umgesetzt |
| P1 | Union-CRDT (G-Set) auf Node-Paar, `public`-Scope. | ✅ umgesetzt |
| P2 | `group:*` + `user:*`; TenantContext-Scoping (MTAA-Isolation). | ✅ umgesetzt |
| P3 | Axiom-Immuntabilität beim Merge + Retract/Tombstone (OR-Set), HLC-Ordnung. | ✅ umgesetzt |
| P4 | Decay (7.1–7.3) abgeleitet — umgesetzt; **Pruning (7.4)**: umgesetzt (Retention + VACUUM-Fenster + Peer-Cursor-Sicherheit). | ✅ umgesetzt |
| P5 | Autoritäts-Node-Modus, Large-Pagination, Monitoring. | ⏳ offen |

---

## 14. Verworfen / Nicht gewählt

- **Synchrone 2PC über Nodes:** zu hohe Latenz; verwirft AP (2.4).
- **Destruktives Autoritäts-Clipping beim Merge:** widerspricht Union/AGM-Historisierung
  (hierarch — stattdessen query-time Autorität, Abschnitt 6).
- **Replikation von `repo:*` / Workspace-Zustand:** gehört zu `dsh-workspace-tx`, nicht Memory.
- **Globale Wanduhr/TSO:** nicht machbar; HLC robuster (2.3).
- **Replizierte Embeddings als primäre Cross-Node-Suche:** Heap/Latenz; node-lokal bleibt.
- **Decay als replizierter Mutier-State:** bricht Konvergenz (7.1).

---

## 15. Entscheidungen (aus Offenen Fragen aufgelöst)

| # | Frage | Entscheidung | Begründung |
|---|---|---|---|
| Q1 | **HLC-Migration** | `facts` erhält `tx_counter INTEGER` + `tx_node TEXT`; Migration via bestehendem Muster (`engine.ts:51-118`); Backfill `tx_node = origin nodeId`, `tx_counter = 0`. | Rückwärtskompatibel; `id`/`tx_from` bleiben, HLC nur zusätzliche Ordnung. |
| Q2 | **Biscuit-Bootstrap** | Ziel = **Biscuit (Zero-Trust, `formal-foundations §5`)**; **P1-Initiale** über dem vertrauten Tailscale-Overlay nutzt **HMAC-signierte Payload** (Konvention aus `dsh-auth`, HMAC-SHA256) mit eingebetteten `tenant`/`scope`-Caveats; Upgrade auf `biscuit-wasm` in P0b. | Biscuit in Node = **WASM-Binding** (`@biscuit-auth/biscuit-wasm`), kein Nix-Paket, schwer zu vendoren. Tailscale ist bereits vertrauenswürdig; HMAC ist ein sounder, wasm-freier Interim. Root-Key per-Cluster aus SOPS. |
| Q3 | **Autoritäts-Node vs. Full-Mesh** | **Hybrid-Default:** pro `tenantContext` eine `role ∈ {authority, replica}`; Authority = Ein-Schreiber (Union-Merge zu Lesern), Replica = Pull. Volle Union (Multi-Authority) opt-in. | Konzentriert Lattice-Durchsetzung an der Authority; Merge-Overhead entfällt im Normalfall. |
| Q4 | **CozoDB-Divergenz (G9)** | Protokoll bleibt **engine-agnostisch** (Union über Versionen, unabhängig vom Storage). SQLite bleibt real; CozoDB/HNSW ist bewusstes Langfrist-Zielbild. | Datenschema-übergreifend; kein Vendor-Lock-in. |
| Q5 | **`node:sqlite` VACUUM** | **Verifiziert funktionsfähig** (`VACUUM` + `incremental_vacuum` OK). Pruning läuft im dedizierten `vacuumIntervalSeconds`-Fenster ohne parallelen Sync (Single-Writer-Scheduling, WAL). | Evidenz: lokaler Test; kein DB-Blocker für E15-Readiness. |

---
*Revidierte Spezifikation, konsistent mit `multi-tenancy.md`, `memory-architecture.md`,
`formal-foundations-and-invariants.md` und `distributed-agent-mesh.md`. Codenzübel als Nachweis in Abschnitt 1.*
