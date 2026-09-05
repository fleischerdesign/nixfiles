# Formal Specification: UI/UX Architecture, Slot Composition & Human-in-the-Loop Ergonomics

Diese Spezifikation definiert die formale Benutzeroberflächen- und Ergonomie-Architektur (**Human-Agent Interaction, HAI**) für `dsh`. Sie basiert auf dem nativen, typisierten **Slot- und Observable-System von `@deepseek-ai/dsh-client-ui-slots`** und integriert das transaktionale Multi-Repo-Modell (MR-2PC), die bitemporale Wissensrepräsentation und das Multi-Host-Mesh in ein konsistentes, haptisches und fehlerresistentes Gesamtsystem.

---

## 1. Ergonomie-Philosophie & Kognitive Schutzprinzipien

In autonomen Multi-Agenten-Systemen entscheidet die Schnittstelle über das Vertrauen und die Fehlertoleranz des Entwicklers. Wir formulieren drei unverrückbare Prinzipien:

1. **Reversibility Invariant (Keine blinde Mutation):**
   Keine destruktive Aktion (Git-Merge, Secret-Änderung, Push) darf ohne visuelle Verifikation und explizite Freigabe im *Approval-Slot* den isolierten Worktree verlassen.
2. **Cognitive Load Reduction (Progressive Disclosure):**
   Detaillierte Verifikations-Logs (`statix`, `deadnix`, Compiler-Ausgaben) werden nicht als unleserliche Textwände in die Chat-Timeline geworfen, sondern in hierarchisch einklappbaren, statuscodierten Disclosure-Panels aggregiert.
3. **Temporal Awareness (Visuelle Zeitreise):**
   Das Gedächtnis des Agenten (Wissensgraph) ist kein statischer Zustand, sondern besitzt einen interaktiven Zeitreise-Schieberegler ($asOf(T_{\text{valid}})$), um Architekturänderungen über Zeit historisch nachzuvollziehen.

---

## 2. Technische Integration: Das dsh Slot-Kompositionsmodell

`dsh` erzwingt eine strikte Trennung zwischen Daten, Rendering und Slot-Zuordnung. Alle neuen Benutzeroberflächen klinken sich über typisierte Module per Declaration Merging in `SlotMap` ein.

```
+------------------------------------------------------------------------------------+
|                         dsh Web-Client Shell (React 19)                            |
+------------------------------------------------------------------------------------+
       |                                              |
       v (Top-Bar Header Slot)                        v (Sidebar Slot)
+-------------------------------+              +-------------------------------+
| Mesh Node Topology Strip      |              | Multi-Tenant Profile Selector |
| (5 Hosts, RTT, Heartbeats)    |              | (Switch Context & Quotas)     |
+-------------------------------+              +-------------------------------+
       |
       v (Conversation Stream / Message Tail Slot)
+------------------------------------------------------------------------------------+
| Transaction Approval Panel (MR-2PC Inspector)                                      |
|                                                                                    |
|  [✓ statix]  [✓ deadnix]  [✓ flake-check: 5 hosts passed]                         |
|                                                                                    |
|  +------------------------------------------------------------------------------+  |
|  | Diff Navigator: repo: nixos (3 files) | repo: forgejo-api (1 file)           |  |
|  | [Side-by-Side Monaco Diff Viewer with syntax highlighting & folded context]   |  |
|  +------------------------------------------------------------------------------+  |
|                                                                                    |
|  [ ✓ Commit & Merge to HEAD ]          [ ✗ Abort & Revert Worktree ]              |
+------------------------------------------------------------------------------------+
       |
       v (Settings Tab Extension Slot)
+------------------------------------------------------------------------------------+
| CozoDB Knowledge Graph Explorer (Force-Directed Graph with Bitemporal Timeline)    |
+------------------------------------------------------------------------------------+
```

### 2.1 Das Four-Share Props Modell

Jede unserer UI-Komponenten implementiert den typsicheren `ComposedProps`-Vertrag:

$$\text{Props} = \text{RuntimeShare} \cap \text{ChildRenderShare} \cap \text{StoreShare} \cap \text{BusinessShare}$$

- **RuntimeShare:** Session-ID, Tenant-Identität, Host-ID.
- **ChildRenderShare:** Rekursiv verankerte Sub-Slots.
- **StoreShare (`defineStore`):** Reaktiv gebundener State (Zustand des Worktree-Diffs, Selektion aktiver Zeilen).
- **BusinessShare (`inject`):** RPC-Methoden zur Host-Ebene (`ctx.connection.invoke('worktree.commit', txId)`).

---

## 3. Kernkomponenten im Detail

### 3.1 Der MR-2PC Transaction Inspector (`ui-worktree-approval`)

* **Slot:** `session.approval.chain` (in `@deepseek-ai/dsh-client-ui-approval`).
* **Trigger:** Agent ruft das Tool `dsh-worktree:propose-commit` auf.
* **UI-Elemente:**
  1. **Verification Gate Badges:**
     - Grünes Badge: `nixfmt`, `statix`, `deadnix` (ohne Warnungen).
     - Status-Badge für `nix flake check` mit Evaluierungs-Dauer und gecachten Derivations-Treffern.
  2. **Multi-Repo Split-View:**
     - Tabs für jedes involvierte Repository ($R_1, R_2, \dots, R_m$).
     - Reaktiv gerendertes Monaco-Diff-Panel mit Single-Click-Line-Discarding.
  3. **Dual-Action Buttons:**
     - Primär (Grün): `Approve & Fast-Forward Merge` (löst Phase 2 des 2PC aus).
     - Sekundär (Rot/Ghost): `Reject & Drop Worktree` (bricht Transaktion ab und stellt vorherigen Zustand wieder her).

---

### 3.2 Mesh Topology & Live Status Strip (`ui-mesh-topology`)

* **Slot:** `layout.header.status.list` (in `@deepseek-ai/dsh-client-ui-layout`).
* **Funktion:** Visuelle Überwachung des verteilten Netzes über Tailscale.
* **UI-Elemente:**
  - Kompakte Badges für alle 5 Hosts:
    - `jello` (Desktop): Grün (Aktiv, Latenz: `< 2ms`)
    - `yorke` (Notebook): Gelb/Grau (Sleep / Offline)
    - `mackaye` (VPS Core): Grün (Master, Load: `0.15`)
    - `rollins` (Collector): Grün (Agent-Worker bereit)
    - `strummer` (Storage): Grün (ZFS ARC: `4.2 GB`, Disks: OK)
  - Hover-Flyout mit Tailscale-IP, aktuellem Lease-Status und CPU/Speicher-Auslastung.

---

### 3.3 Bitemporaler Knowledge Graph Explorer (`ui-knowledge-graph`)

* **Slot:** `settings.tabs.keyed` (in `@deepseek-ai/dsh-client-ui-settings-plugins`).
* **Funktion:** Visualisierung der bitemporalen CozoDB-Datenbank.
* **UI-Elemente:**
  1. **2D Force-Directed Graph:**
     - Knoten repräsentieren Entitäten (Hosts, Services, Module, IP-Adressen).
     - Kanten zeigen typisierte Datalog-Relationen (`bindsPort`, `dependsOn`, `tracks`).
     - Farbkodierung nach Sicherheitsgittern ($\mathbf{l} \in \mathcal{S}$).
  2. **Der Bitemporale Schieberegler ($asOf$):**
     - Ein Slider am unteren Bildschirmrand erlaubt das Scrubbing über die Transaktionszeit:
       $$\text{View}(t) = \text{Render}(\mathcal{K} \text{ asOf } T_{\text{valid}} = t)$$
     - Der Graph mutiert live im Browser: Knoten ploppen auf oder erlöschen je nach historischer Gültigkeit.

---

### 3.4 Multi-Tenancy & Quota HUD (`ui-tenant-hud`)

* **Slot:** `sidebar.footer.single` (in `@deepseek-ai/dsh-client-ui-sidebar`).
* **Funktion:** Transparenz über Token-Verbrauch und Berechtigungen.
* **UI-Elemente:**
  - Aktives Profil (`philipp` vs. `family-member`).
  - Verbleibendes Token-Bucket-Budget (Tageslimit und Monatsbudget als eleganter Progress-Ring).
  - Sicherheitsstufe (z. B. `Level: Operator [Full Worktree Access]` oder `Level: User [Read-Only Memory]`).

---

## 4. UI-Paketierungs- und Registrierungs-Invariante

Um strikte Modularität und Upstream-Kompatibilität zu wahren:
1. Alle UI-Erweiterungen werden als eigenständige Client-Pakete unter `features/dev/dsh/client/<name>/` strukturiert.
2. Der Build erfolgt über `tsdown` (identisch zum Upstream-Monorepo).
3. Die Aktivierung erfolgt deklarativ über `cordis.patch.yml`:
   ```yaml
   # Client-Module Registrierung im cordis.patch.yml
   client:
     - "@deepseek-ai/dsh-client-ui-worktree-approval"
     - "@deepseek-ai/dsh-client-ui-mesh-topology"
     - "@deepseek-ai/dsh-client-ui-knowledge-graph"
   ```

---

## 5. Zusammenfassung

Dieses UI/UX-System macht die theoretische Strenge von `dsh` für den menschlichen Nutzer unmittelbar greifbar:
- **Sicher:** Diffs werden vor dem Merge visuell auditiert.
- **Transparent:** Verteilter Mesh-Status und Quotas sind permanent sichtbar.
- **Innovativ:** Der bitemporale Wissensgraph wird interaktiv erfahrbar gemacht.
- **Konsistent:** 100% kongruent mit dem `@deepseek-ai/dsh-client` Slot- und Design-System.
