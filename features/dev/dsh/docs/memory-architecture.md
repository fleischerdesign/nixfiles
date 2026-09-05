# Formal Specification: Distributed Bitemporal Knowledge Representation & Lattice-Datalog Memory Architecture

Diese Spezifikation definiert die formale Wissensarchitektur (**Knowledge Representation & Reasoning, KR&R**) für das autonome Multi-Tenant- und Peer-Mesh in `dsh`. Sie eliminiert unstrukturierte Speicherformate vollständig zugunsten einer mathematisch fundierten, bitemporalen Deductive Database auf Basis von **Lattice-Based Datalog ($\text{Datalog}^\mathcal{L}$)**, integriertem **Metric-Space Indexing (HNSW)** und **Conflict-Free Replicated Data Types (CvRDT)** zur provokationsfreien Replikation über das Tailscale-Mesh.

---

## 1. Mathematische Grundlagen & Datenmodell

Das Gedächtnis des verteilten Agenten-Systems wird formal als bitemporaler, probabilistischer Wissens-Hypergraph $\mathcal{K}$ modelliert.

### 1.1 Das typisierte Hexatupel (Knowledge Primitive)

Die atomare Informationseinheit ist kein unstrukturierter Textblock, sondern ein streng typisiertes Oktatupel (erweitertes Hexatupel mit Sicherheitslabel und Konfidenzgewicht):

$$\mathcal{F} = \langle s, p, o, T_{\text{valid}}, T_{\text{tx}}, \tau, c, \mathbf{l} \rangle$$

Wobei:
* $s \in \mathcal{U}$ (**Subject URI**): Global eindeutiger Entitäts-Identifikator (z. B. `urn:nix:host:strummer`, `urn:pkg:caddy`).
* $p \in \mathcal{P}$ (**Predicate**): Typsichere Relation aus einer formalen Ontologie (z. B. `sys:bindsPort`, `nix:hasOption`, `infra:dependsOn`).
* $o \in \mathcal{U} \cup \mathcal{L}_{\tau}$ (**Object**): Ziel-Entität oder typisierter Literalwert aus der Algebra $\mathcal{L}_{\tau}$.
* $T_{\text{valid}} = [t_{vs}, t_{ve}) \subset \mathbb{R} \cup \{+\infty\}$ (**Valid-Time Intervall**): Realweltliche Zeitspanne, in der der Fakt zutrifft.
* $T_{\text{tx}} = [t_{ts}, t_{te}) \subset \mathbb{R} \cup \{+\infty\}$ (**Transaction-Time Intervall**): Systemzeit der Persistierung (Append-Only Historie).
* $\tau \in \mathcal{T}$ (**Type Constraint**): Algebraischer Typ (z. B. $\text{IPv4}$, $\text{CIDR}$, $\text{SemVer}$, $\text{DerivationHash}$).
* $c \in [0, 1]$ (**Epistemic Confidence**): Bayesianische Konfidenz der Modell-Inferenz.
* $\mathbf{l} \in \mathcal{S}$ (**Security Clearance Label**): Element aus dem Sicherheitsgitter $\mathcal{L}_{\text{sec}}$ (siehe Abschnitt 3).

---

## 2. Inferenz-Algebra: Lattice-Based Datalog ($\text{Datalog}^\mathcal{L}$)

Zur deduktiven Abfrage und Konsolidierung nutzt `dsh` eine eingebettete Datalog-Engine mit stratifizierter Negation und Gitter-Fixpunkt-Semantik.

### 2.1 Deduktive Regeln & Rekursion

Wissensbeziehungen über Systemgrenzen werden relational und transitiv abgeleitet:

$$\text{TransitiveDependency}(x, y) \leftarrow \text{DirectDependency}(x, y)$$
$$\text{TransitiveDependency}(x, z) \leftarrow \text{DirectDependency}(x, y) \wedge \text{TransitiveDependency}(y, z)$$

### 2.2 Fixpunkt-Semantik

Sei $\mathcal{T}_{\mathcal{P}}$ der monotone Konsequenz-Operator eines Datalog-Programms $\mathcal{P}$. Der Zustand des Gedächtnisses zum Transaktionszeitpunkt $t$ entspricht dem kleinsten Fixpunkt (Least Fixed Point, LFP):

$$\text{LFP}(\mathcal{T}_{\mathcal{P}}) = \bigsqcup_{n=0}^{\infty} \mathcal{T}_{\mathcal{P}}^n(\emptyset)$$

Dadurch sind Endlosschleifen bei zirkulären Abhängigkeiten im Wissensgraphen mathematisch ausgeschlossen.

---

## 3. Formale Multi-Tenancy Harmonisierung: Lattice Information Flow

Die Multi-Tenancy-Garantie aus [multi-tenancy.md](file:///etc/nixos/features/dev/dsh/docs/multi-tenancy.md) wird direkt in die Datalog-Inferenz integriert.

### 3.1 Sicherheitsgitter $\mathcal{L}_{\text{sec}}$

Das Gitter ist definiert als:

$$\mathcal{L}_{\text{sec}} = \langle \mathcal{S}, \sqsubseteq, \sqcup, \sqcap, \bot, \top \rangle$$

Mit $\bot = \text{Public/System}$ und $\top = \text{Restricted/Root}$.

### 3.2 Monotone Informationsfluss-Invarianz

Wenn eine Inferenzregel aus bestehenden Prämissen einen neuen Fakt ableitet:

$$\text{Head}(x, z, \mathbf{l}_{\text{head}}) \leftarrow \text{Body}_1(x, y, \mathbf{l}_1) \wedge \text{Body}_2(y, z, \mathbf{l}_2)$$

wird das Sicherheitslabel des abgeleiteten Wissens strikt über den Join-Operator berechnet:

$$\mathbf{l}_{\text{head}} = \mathbf{l}_1 \sqcup \mathbf{l}_2$$

### 3.3 Mathematische Leak-Freiheit (Query Isolation)

Ein Agent oder Tenant mit Clearance-Level $l_{\text{tenant}}$ führt Anfragen unter einem Projektionsfilter aus:

$$\mathcal{K}_{\text{visible}}(l_{\text{tenant}}) = \{ \mathcal{F} \in \mathcal{K} \mid \mathcal{F}.\mathbf{l} \sqsubseteq l_{\text{tenant}} \}$$

Informationen höherer Vertraulichkeitsstufen sind im Beweisbaum des Datalog-Solvers nicht existent ($P(\text{Leak}) = 0$).

---

## 4. Peer-to-Peer Mesh Synchronisation: CvRDT Konvergenz

Im Einklang mit [distributed-agent-mesh.md](file:///etc/nixos/features/dev/dsh/docs/distributed-agent-mesh.md) operieren die Knoten (`jello`, `yorke`, `mackaye`, `rollins`, `strummer`) als partiell getrenntes Peer-Netzwerk.

### 4.1 Bitemporales State-based CRDT (CvRDT)

Da Fakten $\mathcal{F}$ immutable sind (Append-Only; Änderungen erzeugen einen neuen Fakt mit $T_{\text{valid}}$ Gültigkeitsfenster), ist die Wissensdatenbank ein **Grow-Only Set (G-Set)** bzw. ein **Observed-Remove Set (OR-Set)** bezüglich der logischen Gültigkeit:

$$\mathcal{K}_{\text{merged}} = \mathcal{K}_{\text{NodeA}} \cup \mathcal{K}_{\text{NodeB}}$$

### 4.2 Mathematische Eigenschaften des Merge-Operators $\sqcup_{\text{CRDT}}$

Für alle Zustände $\mathcal{X}, \mathcal{Y}, \mathcal{Z}$:
1. **Kommutativität:** $\mathcal{X} \sqcup \mathcal{Y} = \mathcal{Y} \sqcup \mathcal{X}$
2. **Assoziativität:** $(\mathcal{X} \sqcup \mathcal{Y}) \sqcup \mathcal{Z} = \mathcal{X} \sqcup (\mathcal{Y} \sqcup \mathcal{Z})$
3. **Idempotenz:** $\mathcal{X} \sqcup \mathcal{X} = \mathcal{X}$

**Garantie:** Knoten wie das Notebook `yorke` können im Offline-Betrieb beliebige neue Fakten ableiten. Sobald ein Tailscale-Heartbeat `mackaye` erreicht, konvergiert das Wissen deterministisch und ohne Distributed Locks in Strong Eventual Consistency (SEC).

---

## 5. Physische Speicherarchitektur & Engine-Evaluation

Zur Vermeidung von externem Daemon-Overhead und unberechenbarem Ressourcenverbrauch setzt `dsh` auf eine eingebettete, native Engine-Architektur.

```
+------------------------------------------------------------------------------------+
|                         dsh Agent Cognitive Layer                                  |
+------------------------------------------------------------------------------------+
       |                                                              |
       | Relational & Deductive Query                                 | Dense Vector Search
       v                                                              v
+------------------------------------------------------------------------------------+
|               Embedded Engine Core (CozoDB / RocksDB Storage Engine)               |
|                                                                                    |
|   +---------------------------------------+  +---------------------------------+   |
|   | Datalog Execution Engine              |  | HNSW Vector Metric Space        |   |
|   | - Stratified Negation                 |  | - Cosine Distance in R^d        |   |
|   | - Fixpoint Recursion                  |  | - SIMD Vectorized Distance Calc |   |
|   | - Graph Traversals (PageRank, Paths)  |  |                                 |   |
|   +---------------------------------------+  +---------------------------------+   |
|                                      |       |                                     |
|                                      v       v                                     |
|   +----------------------------------------------------------------------------+   |
|   | Append-Only LSM-Tree / WAL Storage Layer (Storage Backend: RocksDB)        |   |
|   +----------------------------------------------------------------------------+   |
+------------------------------------------------------------------------------------+
```

### 5.1 Engine-Auswahl: CozoDB

Als Kerntechnologie wird die Open-Source-Engine **CozoDB** evaluiert und spezifiziert:
- **Embedded Rust Core:** Kein externer JVM-, Python- oder Cloud-Dienst. Läuft als Zero-Dependency C-FFI / Rust-Binary direkt im Adressraum des Agenten.
- **Datalog + Graph-Algorithmen:** Native Unterstützung für rekursives Datalog, PageRank, Floyd-Warshall und Shortest-Path-Berechnungen.
- **Integrierter Vektor-Index (HNSW):** Nahtlose Kombination von Vektorsuche und relationalen Datalog-Prädikaten in einer einzigen transaktionalen Abfrage.
- **Storage-Backends:** Deterministic In-Memory (für flüchtige Task-Sessions) oder persistentes RocksDB-Backend (`/var/lib/dsh/tenants/<tenant-id>/knowledge.db`).

---

## 6. Integration mit der deklarativen NixOS-Infrastruktur

Das Wissen über das Gesamtsystem wird in zwei kohärente Schichten getrennt:

### 6.1 Statische Wissens-Projektion (Build-Time)
Während des Nix-Builds (`mkSystem`) extrahiert ein Generator aus der Flake-Konfiguration alle statischen Topologie- und Service-Invarianten:
- Alle Hosts, Rollen, Netzwerk-IPs, Ports und Service-Optionen werden als unveränderliche Fakten mit $T_{\text{valid}} = [t_{\text{build}}, +\infty)$ und $\mathbf{l} = \bot$ in die initiale Knowledge-Base kompiliert.

### 6.2 Dynamische Wissens-Konsolidierung (Runtime Reflection)
- Nach Ausführung eines Reparatur- oder Entwicklungs-Tasks extrahiert die Reflection Engine atomare Erkenntnisse.
- **Konfidenzfilter:** Nur Fakten mit $c \ge 0.85$ werden im persistenten LSM-Tree verankert.
- **Konsistenz-Guard:** Versucht ein Agent einen Fakt zu committen, der bestehenden NixOS-Assertions widerspricht, weist der Datalog-Constraint-Checker die Transaktion zurück.

---

## 7. Zusammenfassung

Diese Architektur ersetzt naive RAG-Systeme und unstrukturierte Textnotizen durch ein mathematisch geschlossenes System:
1. **Typensicherheit:** Jede Wissenseinheit ist ein typisiertes Hexatupel mit expliziten Gültigkeitsintervallen.
2. **Multi-Tenancy:** Formaler Beweis der Leak-Freiheit via $\text{Datalog}^\mathcal{L}$.
3. **Verteiltes Mesh:** Konfliktfreie Replikation über das Tailscale-Netzwerk durch CvRDT-Eigenschaften.
4. **Performance & Auditierbarkeit:** Embedded CozoDB-Engine mit $O(\log N)$ LSM-Tree-Speicherung und deterministischen Zeitanfragen ($asOf$).
