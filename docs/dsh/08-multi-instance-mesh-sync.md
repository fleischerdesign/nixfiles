# Agnostic Multi-Instance Memory Sync via Mesh (Family / Colleagues / Friends)

**Status:** Spezifikation — *Entwurf, Basis für Implementierung*  
**Anker:** Alle dsh-Instanzen teilen **einen OIDC-IdP (Authentik)**; User-Subject und Gruppen-Claims sind instanzübergreifend konsistent.  
**Memory-Modell:** **A — instanzweites scoped Memory** (eine `knowledge.db` pro Instanz; `public`/`group`/`user` regeln die Sicht).  
**Replikations-Prinzip:** agnostisch, **keine Hand-gepflegten Peers**; Scope→Peer-Ableitung aus **Presence** (Mesh-Heartbeat) + OIDC-Identität/Gruppen.

---

## 0. Abstrakt & Motivation

`dsh-memory` C7 repliziert derzeit Facts zwischen **deklarativ gelisteten Peers** (`replication.peers: [ {nodeId, endpoint, scopes}, … ]`). Das funktioniert für ein festes, bekanntes Set an Hosts. Für ein agnostisches Szenario —
**beliebig viele Instanzen, nutzbar von Familie, Kollegen, Freunden, lokal oder auf irgendeinem Server** — ist das zu starr: man wüsste nie von Hand, wer wo ist.

Diese Spezifikation formalisiert ein **agnostisches Modell**: Instanzen lernen einander über eine **Presence-Registry** (im existierenden Mesh-Heartbeat), leiten daraus+aus OIDC-Gruppen/-Identity automatisch ab, **welche Instanz** für welchen Scope relevant ist, und synchronisieren nur dorthin. Ergebnis: *mehrere Instanzen, benutzbar von allen, wenn der/die User es wollen* — ohne statische Peer-Konfiguration und ohne Tenant-Leaks.

---

## 1. Systemmodell

### 1.1 Entitäten

- **Instance** `n ∈ N` — eine unabhängige dsh-Instanz (Node), identifiziert durch `nodeId`.
- **Tenant** `u` — authentisierter OIDC-User, gekennzeichnet durch **Subject** (`sub`) und **Gruppen-Claims** (`groups[]`).
- **Group** `g` — OIDC-Gruppe, z. B. `family`, `dev`, `friends`.
- **Scope** `s ∈ {public, group:<g>, user:<u>, repo:<r>}`.
- **PresenceRegistry** — die Menge, welche Instanz welche Tenant/Gruppe hostet.

### 1.2 Identity-Anker (Shared IdP)

Sei `IdP` der gemeinsame OIDC-Provider. Für jede Instanz gilt:

```
sub_n(u) = sub(u)      ∀ n           // gleicher Subject überall
groups_n(u) = groups(u) ∀ n          // gleiche Gruppen-Claims überall
```

Gilt das (übereinstimmend gewählt), ist die Identität **instanzübergreifend eindeutig** — die Grundlage für agnostische Scope-Zuordnung. Wenn eine Instanz denselben IdP nicht teilt, fällt sie aus dem gemeinsamen Modell (sie wird als isolierter Fremd-Node behandelt; Replikation dorthin nur `public`/explizit).

### 1.3 Memory-Modell A (instanzweites scoped Memory)

Jede Instanz hält **eine** `knowledge.db`. Kein per-Tenant-DB-Erzwingen (im Gegensatz zu MTAA §3; Begründung in §3.1). Die Sichtbarkeit regelt die bestehende **Scope-Lattice**:

```
canSee(u, fact):
  public → true
  group:<g> → g ∈ u.groups
  user:<u'> → u' == u
  repo:<r> → owned by u (repo-scope, node-gebunden)
```

---

## 2. Presence-Registry

### 2.1 Definition

Jede Instanz **adwertisiert** ihre lokal gehosteten `tenant`s und `groups`:

```
presence(n) = {
  nodeId: n,
  tenants: [ { sub: <oidc-subject>, username: <u> } ],  // von lokalen authentifizierten Identitäten
  groups:  [ 'group:family', 'group:dev', ... ],
  updatedAt: <ts>,
  healthy: bool
}
```

### 2.1.1 Presence-Datenquelle (empirisch verifiziert)

> **Befund:** `dsh-auth` führt heute **keine Registry** der lokal authentifizierten Tenants —
> nur `activeTenant` (die Identität des aktuellen Request) und `tokenBuckets` (Quota-Keyed
> nach Tenant). Es gibt kein persistentes "wer hat hier eine Session" — **keine** Enumerierbarkeit
> der gehosteten Tenants/Gruppen.

Daraus folgt eine **neue Voraussetzung für P0**: ein **Tenant-Presence-Registry-Subsystem** in
`dsh-auth`, das bei jedem gültigen `UserIdentity` (session-cookie-Validierung → `activeTenant`,
`auth/src/index.ts:104-167`) die Tenant-ID + `username` + `groups` **persistiert** (z. B.
`~/.dsh/auth/presence.db`, `INSERT OR IGNORE`, rückwirkend via `updatedAt`). Sodann:

```
presence(n).tenants = { (tenantId, username) : present }
presence(n).groups   = union over present tenants of their OIDC groups-claims
```

- **Konsistenz:** Presence ist eine **Annäherung** (nur Identitäten, die mind. einmal authentifiziert
  wurden). Ein Tenant, der nie hier war, taucht nicht auf → dessen `user:<u>` replicated hierhin
  nicht (korrekt: sein Wissen liegt nicht auf dieser Instanz).
- **Pruning der Registry:** Tenants ohne Aktivität > `presenceTenantTtl` werden als abwesend gewertet
  (offline), nicht sofort gelöscht (Replikations-Cursor bleibt konsistent).



### 2.2 Transport

Die Presence wandert **im bestehenden Mesh-Heartbeat** (`dsh-mesh` `/mesh/heartbeat` / `pollPeers`). Der Heartbeat-Payload wird um `presence` erweitert. Jede Instanz aggregiert die Presence **aller erreichbaren Instanzen** in einer lokalen Registry `P = { presence(n) : ∀ n healthy }`.

### 2.3 Register-Aktualisierung

- Bei jedem OIDC-Login / Gruppenwechsel aktualisiert die Instanz ihr `presence`.
- `updatedAt`-Frische: Presence älter als `presenceTtl` (z. B. 2× Heartbeat) wird als offline gewertet → Replikation zu dieser Instanz pausiert.
- **Agnostisch:** Instanzen, die dazukommen/weniger werden, fließen automatisch über P — keine Hand-Liste.

---

## 3. Scope→Peer-Ableitung (agnostisch)

Aus `P` plus OIDC leiten wir für **jeden** zu replizierenden Scope die Ziel-Peers ab — ohne manuelle `peers`:

### 3.1 Ableitungsregeln

```
localSub(u)  = das eigene OIDC-Subject dieser Instanz (aus tenantContext "user:<u>")

peers(public,  u)    = { n ∈ P.healthy }                          // opt-in (Menge per config.scopes)
peers(group:<g>, u)  = { n ∈ P.healthy | g ∈ presence(n).groups }
peers(user:<u>,  u)  = { n ∈ P.healthy | u == localSub(u) }       // NUR eigenes Subject!
peers(repo:<r>,  u)  = ∅  (standardmäßig nie repliziert)
```

**Korrekturekton (Privacy, empirisch verifiziert):** Der `user:<u>`-Scope wird nach dem
**lokalen Subject** gated, nicht nach der Peer-Presence. Sonst würde eine Instanz das
privates Wissen fremder User ziehen, bloß weil der Peer sie hostet (Leak). Zusätzlich
setzt die **Serve-Seite** `user:<u>` nur an den Eigentümer durch (I-SEC2): eine
Multi-Tenant-Instanz verlangt **keinen** exakten `tenantContext`-Vergleich, sondern
prüft pro angefragtem Scope `user:<u>` → nur wenn `token.sub == user:<u>`.

- **Gruppenwissen** (`group:<g>`): wird an **alle** Instanzen gespiegelt, die mindestens ein Mitglied von `g` hosten.
- **Privates User-Wissen** (`user:<u>`): nur an Instanzen, die **dieselbe OIDC-Subject `u`** *abrufen* (folgt dir über Geräte/Instanzen), nie an fremde Tenant-Instanzen.
- **Public:** nur wenn der jeweilige Peer-Agent `public` in seiner `scopes`-Allowlist hat (I-SEC8).

### 3.2 Tenant-Grenze (MTAA-Reconciliation)

> **Wichtige Abgrenzung zu MTAA §3:** MTAA spezifiziert per-Tenant-DB-Isolation. Modell A wählt instanzweites, **scoped** Memory statt. Die **Isolation bleibt gewahrt** (I-SEC2/I-SEC4: wasser-dichtes `canSee` auf Empfängerseite, nie über Tenant-Grenze), aber die **Physische DB-Grenze** ist die Instanz, nicht der Tenant. Für teil-vertraute Teilnehmer (Familie/Kollegen/Freunde) ist das korrekt; für unvertraute Fremd-Tenants wäre Modell B (per-Tenant-DB) zu wählen. Diese Entscheidung wird bewusst als **Modellwahl** geführt, nicht als Verstoß.

### 3.3 Sicherheits-Invarianten (erweitert)

- I-SEC8: **Peer-Ableitung ist rein additiv** — ein Scope wird nur zu Instanzen gespiegelt, deren Presence ihn legitimerweise zulässt; die **Empfänger-Seite** setzt `canSee` zusätzlich durch (I-SEC2), sodass eine versehentliche (falsche Presence-)Zustellung **keinen** Datenverlust an Unbefugte verursacht.
- I-SEC9: **Fremd-Instanzen** (anderer IdP / keine Presence) erhalten standardmäßig nur `public` (falls opt-in) — niemals `user:*`/`group:*`.
- I-SEC10: Presence selbst ist **nicht vertraulich** (nur Host-Angaben, keine Facts) und trägt keine Secrets.

---

## 4. Synchronisations-Ablauf

Die bestehende C7-Delta-Replikation bleibt unverändert auf **Prozess-Ebene**; nur die **Peer-Liste + Scope-Zuordnung** wird dynamisch aus `P` abgeleitet:

1. Bei jedem Pull-Zyklus: `peers = derive(targetContext, scopes, P)`.
2. Für jeden Peer einen Capability-Token (I-SEC5) mit den **delegierten Scopes** (`attenuate` auf die jeweilige Scope-Allowlist) ausstellen.
3. Delta abholen (HLC-Cursor), Union-Merge + OR-Set-Tombstones anwenden, Cursor fortschreiben.
4. Presence-Änderungen (Instanz offline/neu) fließen beim nächsten Zyklus ein — **konvergent**.

---

## 5. Edge-Case-Matrix

| # | Edge Case | Erwartung |
|---|---|---|
| M1 | Neue Instanz kommt hinzu | Presence im nächsten Heartbeat; Replikation zu dieser Instanz startet automatisch (public/group, je nach `canSee`). |
| M2 | Instanz geht offline | `presenceTtl` läuft ab → Ziele aus `P` entfernt; Cursor bleibt, Nachholen bei Rückkehr. |
| M3 | User loggt sich auf zwei Instanzen ein (lokal+zentral) | `user:<u>` beidseitig in Presence → privates Wissen folgt dem User. |
| M4 | User wird aus Gruppe entfernt | Presence/Gruppen-Claim aktualisiert → Gruppe spiegelt nicht mehr dorthin; bestehende replizierte `group:*`-Facts erlöschen durch `canSee` (Empfänger lehnt ab). |
| M5 | Instanz mit fremdem IdP | keine gemeinsame Presence → nur `public` (opt-in), nie `user`/`group`. |
| M6 | Race: zwei Gruppe schreiben dasselbe Fact | Union + query-time Rangfolge (Axiom>Evidence>Hypothesis), deterministisch. |
| M7 | Presence liefert falsche Info (Bug) | Empfängerseitiges `canSee` fängt ab (I-SEC2) → kein Leak, nur kein Sync. |
| M8 | Kollege will nur `group:dev`, nicht `public` | `scopes`-Allowlist pro Instanz gate→ `public` nicht gespiegelt. |
| M9 | Sehr viele Instanzen | agnostische Peer-Ableitung skaliert; Delta-Pull via HLC-Cursor bleibt O(Δ). |

---

## 6. Nix-Konfigurationsfläche (agnostisch)

```nix
my.features.dev.dsh.memory.replication = {
  enable = true;
  tenantContext = "user:philipp";   # Replikationsdomäne (MTAA-Grenze)
  secretEnv = "DSH_MEMORY_HMAC";    # Capability-Secret (via Credentials)
  scopes = ["public" "group:dev" "group:family" "user:philipp"];  # was ich teilen will
  listenPort = ...;
  # KEINE `peers` mehr — wird aus Presence(Secure)+OIDC abgeleitet.
};
```

- `peers` (bisher manuell) wird **entfernt/obsolet** → ersetzt durch Presence-Ableitung.
- `scopes` bleibt die **Schutzgrenze**: die Menge, die eine Instanz überhaupt zu teilen bereit ist.

---

## 7. Roadmap & Phasing

| Phase | Inhalt | Gate |
|---|---|---|
| P0 | Presence im Mesh-Heartbeat (`nodeId, tenants, groups, updatedAt`) + lokale Registry `P`. | I-SEC10, Presence-TTL |
| P1 | Scope→Peer-Ableitung `derive(scopes, P)` ersetzt statische `peers`. | I-SEC8/9 |
| P2 | Capability-Attenuation pro abgeleitetem Peer (nur delegierte Scopes). | I-SEC5 |
| P3 | Empfänger-`canSee` Doppel-Durchsetzung (bereits vorhanden) verifiziert gegen Presence. | I-SEC2 |
| P4 | Nix-Oberfläche: `peers` raus, `scopes`+`secret` rein; Spec+isolierte Tests. | M-Tests |

---

## 8. Verworfen / Abgrenzung

- **Strikte per-Tenant-DB (MTAA §3) für alle:** bewusst **nicht** gewählt (Modell A). Reduziertes geteiltes Gruppenwissen; nur für unvertraute Fremd-Tenants.
- **Statische Peer-Listen:** abgelöst durch Presence (Agnostik).
- **Globaler Zentral-Node als einzige Autorität:** nicht gewünscht — Multi-Authority-Union bleibt; jeder trägt bei.

---
*Entwurf der agnostischen Multi-Instanz-Erweiterung auf Basis von C7 (HLEC/Tombstone/Capability) + MTAA. Identity-Anker = gemeinsamer OIDC-IdP.*
