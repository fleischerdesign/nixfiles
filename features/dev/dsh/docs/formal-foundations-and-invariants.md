# Formal Foundations, Invariants & Resilience Architecture

Diese Spezifikation formuliert die mathematischen Fundamente, Invarianten und Beweisgrenzen für das autonome Entwickler- und Infrastruktur-Ökosystem von `dsh`. Sie löst die fünf fundamentalen Verwundbarkeiten autonomer Agentensysteme (Concurrency Contamination, Approval Deadlocks, Halting/Resource Exhaustion, Belief Contradictions und Unbounded Mesh Authority) durch formale Methoden auf.

---

## 1. Storage Isolation & Workspace Concurrency: CoW-OverlayFS & OCC

Herkömmliche Git-Worktrees scheitern in Produktionsumgebungen an shared `.git/index.lock`-Kollisionen, fehlenden untracked Dependencies (`node_modules`, `.venv`) und deterministischen Rebase-Konflikten.

```
                    Host Working Tree (Developer Workspace)
                    +-------------------------------------+
                    | .git/ Ref Storage & Index           |
                    | Untracked Build Caches / Artifacts  |
                    +-------------------------------------+
                                       |
                                       v (Mount Namespace / OverlayFS)
                    +-------------------------------------+
                    | Ephemeral Transaction Space (OCC)   |
                    | Lowerdir: Host Workspace (ReadOnly) |
                    | Upperdir: /tmp/dsh-tx-<uuid>/ (RW)  |
                    +-------------------------------------+
```

### 1.1 Mathematisches Dateisystem-Modell
Sei $\mathcal{W}_{\text{host}}$ der Arbeitsbaum des Entwicklers. Der transaktionale Arbeitsraum $\mathcal{W}_{\text{tx}}$ wird als ephemeres Copy-on-Write (CoW) Layered Filesystem konstruiert:

$$\mathcal{W}_{\text{tx}} = \text{OverlayFS}(\text{lower} = \mathcal{W}_{\text{host}}, \text{upper} = \mathcal{U}_{\text{tx}}, \text{work} = \mathcal{K}_{\text{tx}})$$

- **$O(1)$ Instanziierungszeit:** Alle Abhängigkeiten, Symlinks und Build-Artefakte sind sofort verfügbar, ohne Kopier-Overhead.
- **Index-Lock Isolation:** Schreiboperationen auf `.git/` landen isoliert in $\mathcal{U}_{\text{tx}}$. Parallele `git`-Aufrufe des Entwicklers im Hauptverzeichnis werden zu keinem Zeitpunkt blockiert.

### 1.2 Optimistic Concurrency Control (OCC) & 3-Way Rebase
Jede Transaktion $T$ bindet sich an den initialen Commit-Zustand:

$$C_{\text{base}} = \text{HEAD}_{\text{host}}(t_0)$$

Beim Abschlussversuch zur Zeit $t_1$ gilt die Entscheidungskette:

$$\text{CommitPolicy}(T) = \begin{cases} 
\text{FastForwardMerge}, & \text{wenn } \text{HEAD}_{\text{host}}(t_1) = C_{\text{base}} \\
\text{AttemptRebase}(\Delta_{\text{tx}}, \text{HEAD}_{\text{host}}(t_1)), & \text{wenn } \text{HEAD}_{\text{host}}(t_1) \ne C_{\text{base}} \wedge \text{CleanMerge} \\
\text{FailClosedAbort}, & \text{wenn Konflikt auftritt}
\end{cases}$$

Tritt ein Rebase-Konflikt auf, verwirft das System $\mathcal{U}_{\text{tx}}$ spurlos. Der Haupt-Zweig bleibt zu jedem Zeitpunkt unberührt.

---

## 2. Risk-Stratified Capability Lattices ($\mathcal{R}_0, \mathcal{R}_1, \mathcal{R}_2$)

Um das Dilemma zwischen Blockaden bei unbemannten Hintergrundläufen (z. B. Alert-Healing um 03:00 Uhr) und Systemgefährdung aufzulösen, wird jede Mutation $M$ durch eine Risikofunktion klassifiziert:

$$\text{Risk}: \mathcal{M} \to \{ \mathcal{R}_0, \mathcal{R}_1, \mathcal{R}_2 \}$$

```
                           [R2: Irreversible / Critical]
                           - Secrets, Kernel/Boot, Master HEAD
                           - Erfordert: Asynchrones Human Approval (Lease TTL=24h)
                                        ^
                                        | (Escalation Boundary)
                           [R1: Constrained / Reversible]
                           - Code/Config-Mutationen mit passenden Test-Gates
                           - Erfordert: Optimistic Branch Commit + PR
                                        ^
                                        | (Automation Boundary)
                           [R0: Idempotent / Read-Only]
                           - Log-Analyse, GC, Cache-Reindex
                           - Erfordert: Volle Autonomie (Zero-Intervention)
```

### 2.1 Formales Verhalten bei unbemannten Hintergrund-Tasks
- **$\mathcal{R}_0$ (Vollautonom):** Sofortige Ausführung und Quittierung.
- **$\mathcal{R}_1$ (Optimistische Kapselung):** Der Agent merget nicht nach `HEAD`, sondern erzeugt einen isolierten Branch `agent/task-<uuid>` und sendet eine asynchrone Benachrichtigung via Ntfy/Telegram.
- **$\mathcal{R}_2$ (Human-in-the-Loop Barrier):** Die Transaktion geht in den Zustand `suspended` mit einer Time-to-Live $\text{TTL} = 24\text{h}$ im persistenten Zustands-Speicher. Verstreicht die Lease ohne Freigabe im Web-UI, rollt das System fail-closed zurück.

---

## 3. Bounded Deterministic Execution Envelopes (Gate Containment)

Zur Beherrschung des Halteproblems und zur Verhinderung von Resource-Exhaustion durch beliebige Testskripte wird jeder Verifikationsschritt in einer deterministischen Schranke ausgeführt:

$$\mathcal{E} = \langle \tau_{\text{timeout}}, \text{Mem}_{\text{max}}, \text{CPU}_{\text{quota}}, \text{NetPolicy} \rangle$$

### 3.1 Formale Schrankenparameter
1. **Temporäre Begrenzung:** $\tau_{\text{timeout}} = 120\text{s}$. Nach Ablauf wird der gesamte Prozessbaum via `cgroup.kill` augenblicklich und unwiderruflich beendet.
2. **Speicher- und Rechenschranke:**
   - $\text{Mem}_{\text{max}} = 4\text{ GiB}$, Swap deaktiviert ($\text{SwapMax} = 0$).
   - $\text{CPU}_{\text{quota}} = 200\%$ (Beschränkung auf max. 2 Rechenkerne).
3. **Netzwerk-Isolation:**
   - Standardmäßig hermetisch isoliert (`unshare -n`, nur Loopback-Interface).
   - Egress-Zugriff ist nur zulässig, wenn der Task explizit eine $\mathcal{R}_2$-Capability deklariert.

---

## 4. Epistemische Belief Revision (AGM-Postulate & Evidenzakkumulation)

Treffen im bitemporalen Wissensgraphen zwei Beobachtungen mit logischer Kontradiktion zur selben Valid-Time aufeinander, erzwingt die Engine eine formale Widerspruchsauflösung.

### 4.1 Funktionalitäts-Invariante
Ein Prädikat $p \in \mathcal{P}$ ist funktional, wenn es zu einem Subjekt genau ein Objekt binden darf:

$$\forall s \in \mathcal{U}: |\{ o \mid \exists T_v: \mathcal{F}(s, p, o, T_v) \wedge \text{active}(T_v) \}| \le 1$$

### 4.2 Bayesianische Evidenzakkumulation
Seien $\mathcal{F}_1(s, p, o_1)$ und $\mathcal{F}_2(s, p, o_2)$ mit $o_1 \ne o_2$ im Konflikt. Die effektive Konfidenz berechnet sich aus Quellen-Autorität $w_{\text{src}}$, Modell-Konfidenz $c$ und zeitlichem Zerfall $\lambda$:

$$c_{\text{eff}}(F) = w_{\text{src}} \cdot c_{\text{model}} \cdot e^{-\lambda (t_{\text{now}} - t_{\text{observed}})}$$

- Ist $c_{\text{eff}}(\mathcal{F}_1) - c_{\text{eff}}(\mathcal{F}_2) > \theta_{\text{margin}}$, wird $\mathcal{F}_1$ als aktive Kante im Datalog-Solver verankert; $\mathcal{F}_2$ wird in den Status `disputed` überführt (kein Datenverlust, Historisierung bleibt intakt).
- Liegen beide Konfidenzen innerhalb der Fehlertoleranz $\theta_{\text{margin}}$, blockiert die Engine deduktive Folgerungen über dieses Prädikat und generiert ein *Epistemisches Klärungs-Event* für den Administrator.

---

## 5. Zero-Trust Mesh Autorisierung: Biscuit Capability Tokens

Die Kommunikation zwischen den 5 Hosts (`jello`, `yorke`, `mackaye`, `rollins`, `strummer`) über Tailscale stützt sich nicht auf reine IP-Adressen, sondern auf **kryptographisch abgeschlossene Biscuit-Tokens** mit eingebetteter Datalog-Prüfung.

### 5.1 Token-Struktur
Ein Token $T$ ist eine signierte Kette von Blöcken:

$$T = \text{Sign}_{K_{\text{root}}}(\text{AuthorityBlock} \circ \text{Block}_1 \circ \dots \circ \text{Block}_k)$$

### 5.2 Datalog-Caveat-Verifikation (Local Evaluation)
Der empfangende Host (z. B. `strummer`) verifiziert das Token lokal und autonom, ohne Rücksprache mit einem zentralen Identity-Provider:

```datalog
// 1. Zeitliche Frische (Time-Bounded Lease)
check if time(now), now < 1741219200;

// 2. Host-Boundary Constraint
check if target_host("strummer");

// 3. Risikoschranke (Keine R2-Operationen im Mesh ohne expliziten Key)
check if operation_risk(R), R <= 1;

// 4. Pfadkapselung
check if target_path(P), P.starts_with("/var/lib/dsh/tenants/philipp/");
```

Schlägt ein einziges Caveat im Datalog-Fixpunkt der lokalen Host-Fakten fehl, wird der Request an der Netzwerkschicht verworfen.

---

## 6. Zusammenfassung der Garantien

| Problemklasse | Konventioneller Ansatz | dsh Formaler Standard |
|---|---|---|
| **Git Concurrency** | Naive Worktrees (Lock-Kollision) | **CoW-OverlayFS mit OCC & Clean Rebase** |
| **Approval Deadlocks** | Manuelles Warten / Unbeschränkte Rechte | **Risk Lattices ($\mathcal{R}_0, \mathcal{R}_1, \mathcal{R}_2$) mit Branch-Isolation** |
| **Gate Non-Termination** | Unbegrenzte Shell-Ausführung | **Hermetische Envelopes (cgroup v2, Timeouts, Net-Unshare)** |
| **Memory Contradictions** | LIFO / Zufälliger Überschrieb | **AGM-Belief Revision via Bayesianischer Evidenz** |
| **Mesh Security** | Vertrauen auf Tailscale IP | **Zero-Trust Biscuit-Tokens mit lokalen Datalog-Caveats** |
