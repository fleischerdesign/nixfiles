# Distributed Mesh Capability Authorization (Weg B)

**Status:** Design & Roadmap (not implemented)
**Scope:** Granular, capability-based authorization for the distributed dsh agent mesh, so that trusted-but-bounded principals (family, friends, and the operator's own nodes) can reach and steer other nodes with explicit, attenuable, attestable authority — instead of the current "mesh peer implies Admin" posture.

Cross-references the existing dsh specifications: `multi-tenancy.md`, `distributed-agent-mesh.md`, `memory-architecture.md`, `formal-foundations-and-invariants.md`. The filesystem dimension is specified in [`filesystem-capability-layer.md`](filesystem-capability-layer.md).

---

## 1. Context & Goals

### 1.1 Motivation

The deployment federates dsh across five hosts (jello, yorke, mackaye, rollins, strummer) forming a personal, equal-rights agent mesh over Tailscale, plus a public multi-tenant gateway on rollins (ai.rls.ancoris.ovh) exposed to family/friends via dsh-auth (OIDC against Authentik).

Two distinct trust domains:

| Domain | Hosts | Actor | Trust model |
|---|---|---|---|
| A — Private operator mesh | jello, yorke, mackaye, strummer | the operator (philipp) | shared-secret, equal-rights peers |
| B — Public multi-tenant gateway | rollins | family, friends | OIDC, LBAC lattice, token-bucket quota |

### 1.2 Goals

1. Provable, consistent identity: every dsh session on every host authenticates against a single IdP (Authentik) and resolves to the same principal `user:<oidc-sub>` everywhere. Eliminates `local`/`philipp` fragmentation and the anonymous-`local`-Admin fallback.
2. Granular cross-node authorization: a principal reaches/steers other nodes only within an explicit, attested authority — never a peer-wide blanket Admin.
3. Attenuable, bounded authority: narrowed (resources, actions, time, budget, depth) but never widened.
4. Usable & transparent: declarative grants, role bundles, self-service bounded sharing, audit trail.
5. Agnostic: generic URIs (`user:*`, `group:*`, `node:*`, `tool:*`, `scope:*`, `path:*`) with zero hardcoded usernames/hostnames.

### 1.3 Non-Goals

- Removing the operator's full control of the mesh (operator remains `user:<sub>` Admin by policy).
- Sanitizing readable data content — capability bounds access, not confidentiality.
- Eliminating trusted-but-bounded risk entirely; capability controls authority, not intent.

### 1.4 Honest Framing

No "perfect" security model exists — only a threat model and a coherent design within it. This design assumes: principals are known and OIDC-attested, some may be partially untrustworthy within their grant; any principal holding valid signing authority for a node is a full peer there. Capability is a ceiling of authority, not a judgment of intent.

---

## 2. Problem Statement (as found)

1. **Peer = Admin** — `PeerMeshStrategy.authenticate` returns `clearance: 'Admin'` for any node with a valid HMAC header (`dsh-auth/src/strategy.ts`). No per-tenant/per-action gating at the mesh boundary.
2. **Non-attestable local identity** — `LoopbackStrategy` returns `loopback.defaultUser`; the anonymous cookie fallback (`ensureSessionCookie`) mints `username: 'local'`, `clearance: 'Admin'` regardless of remote IP while `loopback.enabled`. Fragments user-scoped memory into `user:philipp` and `user:local`.
3. **Provenance collision** — `dsh-memory/src/index.ts` uses `replicationNodeId = ... || 'local'` as `originNode` for every fact, even with replication disabled. All non-rollins nodes write origin `local`, breaking the CvRDT total order `(HLC, nodeId)`; cross-node merge becomes ambiguous, provenance misattributed.
4. **Replication not wired** — `memory.replication.enable` defaults `false`, no host sets it; the bitemporal CvRDT cluster is implemented but inactive. Memory is per-host siloed.

---

## 3. Identity Model

### 3.1 Principals

```
user:<oidc-sub>     # human, SSoT (Authentik) — SAME on every host
group:<group>       # Authentik groups, role aggregation
node:<nodeId>       # machines / mesh peers (nodeId = hostname)
```

A human has exactly one identity everywhere (`user:<sub>` from Authentik). Node identity (`node:<hostname>`) is separate: user principal governs scope attribution; node identity governs merge ordering & provenance.

### 3.2 OIDC everywhere, loopback disabled

| Host | dsh-web bind | redirectUri | loopback.enabled |
|---|---|---|---|
| rollins | behind Caddy (public) | https://ai.rls.ancoris.ovh/oidc/callback | false (already) |
| jello, yorke, mackaye, strummer | 127.0.0.1:3080 | http://127.0.0.1:3080/oidc/callback | false |

Loopback redirect URIs are a standard OIDC pattern and identical across the four local hosts, so one public client (PKCE, no secret) covers them; rollins retains its secret client.

Why loopback must be disabled everywhere (incl. the operator's own machines): capability grants are keyed on `user:<oidc-sub>`. A loopback session resolving to `philipp`/`local` is a different principal string and would fail to match the operator's own grants — self-inflicted denial. Consistency is a correctness requirement, not merely security.

### 3.3 Session

Signed session cookie (`dsh-auth`, `sessionTtlDays`) persists the OIDC identity; one IdP round-trip per session.

---

## 4. Capability Model

Authority is expressed exclusively through signed, attenuable capability tokens (OCAP / delegated-token lineage; extends `dsh-memory/capability.ts`, `dsh-share`).

### 4.1 Capability tuple

```
capability := {
  principal: PrincipalURI            # who holds it
  resources: ResourceURI[]           # what it may reach (node/tool/scope/path)
  actions:   ActionSet                # what it may do
  bounds:    { ttl, budgetEur, maxTurns, maxDepth, pathAllowlist[], resourceAllowlist[] }
  attestation: SignedProof            # unforgeable, attenuable, revocable
}
```

### 4.2 Resources & ActionSet

```
node:strummer   node:all
tool:filesystem.read   tool:docker.*
scope:user:<sub>   scope:group:family
path:/etc/nixos/**   path:/mnt/storage/**   (see filesystem-capability-layer.md)
```

Actions (closed, minimal), with the LBAC lattice retained as an ergonomic aggregate. This is the **single canonical verb set** used across the whole model (and by `filesystem-capability-layer.md`); not every verb applies to every resource type:

```
read | list | write | mutate | exec | orchestrate | replicate
```

| Verb | Meaning | Valid resource types |
|---|---|---|
| `read` | open / read / stat a specific object | node, tool, scope, path |
| `list` | enumerate / glob a directory or collection (distinct from `read`; not granted with `read` by default) | path (dir), tool, scope |
| `write` | create / truncate / append within a root | path, scope |
| `mutate` | rename / delete / change state within a root | path, node, scope |
| `exec` | run a process under a granted root | path, node |
| `orchestrate` | instantiate a cross-node task contract | node, tool |
| `replicate` | sync memory facts over the mesh, bounded by scope | scope |

`path:` verbs use the FS layer's matched-by-prefix semantics (§4.4 / `filesystem-capability-layer.md` §4), **not** exact-URI equality.

Lattice expansion (named bundles, still through the evaluator):

| Level | resources | actions |
|---|---|---|
| Restricted | node:public-gateway | read |
| Member | node:<approved> | read, list, exec (media/task/vikunja, bounded) |
| Admin | node:all | read, list, write, mutate, exec, orchestrate, replicate |

### 4.3 Attestation (pluggable; two roots of trust)

- Issuance: signed delegation tokens. Internal operator mesh → symmetric mesh secret (sole actor is the operator). Public/family&friends → asymmetric keypair per principal, signature bound to a public key — the only way to prove who a principal is.
- **Signing/verification is a pluggable backend, not one scheme.** The same capability evaluator must accept both a symmetric-HMAC proof (operator mesh) and an asymmetric signature (public). The evaluator dispatches to the backend that matches the issued token's `alg`; a token is never accepted under a different scheme than the one it was issued with. This keeps the operator mesh simple (no key distribution) while the public domain stays attestable.
- Attenuation / Non-Widening Invariant: a delegated capability may only narrow its parent — never exceed it. Privilege escalation is mathematically excluded (mirrors non-escalation proof in `multi-tenancy.md` §2.2).

### 4.4 Evaluation (target node)

```
authorise(principal, resource, action, now) :=
  ∃ grant G : G.principal dominates principal
            ∧ resource ∈ G.resources
            ∧ action   ∈ G.actions
            ∧ within(G.bounds, now, budget, depth)
            ∧ verify(G.attestation)
            ∧ ¬revoked(G)
```

Fail-closed: no valid capability ⇒ no access. Replaces "mesh peer ⇒ Admin" with per-capability authorization; reuses the LBAC precedence check (`enforceLbacToolPolicy`) as the coarse gate beneath.

**Matching nuance.** `resource ∈ G.resources` is exact-URI equality for `node:`/`tool:`/`scope:` resources, but **delegates to prefix matching for `path:` resources** (see `filesystem-capability-layer.md` §4). A `path:` capability is never matched by string equality on the requested URI.

### 4.5 Cross-Node Principal Attribution (required — the transport only proves the node)

The peer-mesh transport (`PeerMeshStrategy`, `dsh-auth/src/strategy.ts`) authenticates the **node** via an HMAC header (`x-dsh-node`), so a target node learns "this is `node:strummer`" but **not** which OIDC user is acting. This is the crux for "family reaches other nodes": the target must authorize the **user** principal, not merely trust the peer node.

**Mechanism.** Every cross-node call carries a **delegation capability** that:
1. binds the **user principal** (`user:<oidc-sub>`) as the capability's `principal`,
2. is **issued to** (and presented by) a specific `node:<id>` (`sink` = the initiating node), so it cannot be replayed through an unrelated node,
3. is **marked transitive** only when an explicit re-delegation (with non-widening) is authorized; otherwise it is single-hop (`maxDepth = 1`),
4. is validated **on the target node** against the target's own policy — i.e. the outer check in §4.4 is evaluated for `principal = user:<sub>`, **not** for `node:<id>` alone.

**Consequence for `authorise`:** on a cross-node call the effective `principal` passed to the evaluator is the **user** carried in the delegation token, and the node identity is only the transport-level *channel*. The peer-mesh HMAC (node) and the capability (user) are **two separate proofs**; both must validate, and only the user proof determines the grant. This is what makes "a Member tenant may read media on strummer, but not touch its config" enforceable, even though the call enters over a node-authenticated channel.

**Failure mode to avoid:** never evaluate a cross-node call using only the node HMAC. That is exactly the current "peer ⇒ Admin" hole, reintroduced at the transport layer.

---

## 5. Integration with Existing Stack

| Subsystem | Change |
|---|---|
| dsh-auth `PeerMeshStrategy` | node ⇒ evaluated capability (see §4.4) |
| dsh-auth `LoopbackStrategy` | disabled on all hosts; identity always `user:<oidc-sub>` |
| dsh-auth LBAC + token bucket | retained; role = capability bundle; bucket keyed on principal (cost follows principal even cross-node) |
| dsh-memory `capability.ts` | extended with resources/actions/bounds/principal |
| dsh-memory `replication.ts` | `replicate` gated by `scope:` resources (no foreign `user:x` synced as `user:philipp`) |
| dsh-mesh OCAP contracts | carry principal + capability; `maxDepth` guards chains/cycles |
| dsh-workspace-tx | group-gated approval retained for destructive `mutate` |
| dsh-share | mint bounded, time-limited invite-capability URLs, instant revocation |

Agnostic: all URIs/attrsets, no hardcoded usernames/hostnames (feature invariant).

---

## 6. Usability & Ergonomics

1. Declarative grants (operator-written, Nix-versioned):
   ```nix
   my.features.dev.dsh.mesh.grants = {
     "user:<friend-sub>" = {
       roles = [ "member" ];
       nodes = [ "strummer" "mackaye" ];
       tools = { filesystem = [ "read" "stat" ]; };
       bounds = { budgetEur = 3.0; maxTurns = 5; ttl = "P30D"; };
     };
   };
   ```
2. Role bundles (`member`, `admin`) with granular overrides.
3. Self-service bounded sharing (attenuated invite capability, instant revocation).
4. Transparency panel (auth HUD / group switcher) + audit log.

---

## 7. Edge Cases

| Edge case | Handling |
|---|---|
| Replay / interception | TTL + nonce / monotonic counter |
| Privilege escalation | Non-Widening Invariant + `maxDepth` |
| Group membership change | re-check at use time or short-lived re-issue |
| Partition / offline node | fail-closed + lease watchdogs |
| Multi-hop | explicit re-delegation (non-widening) or `maxDepth=1` |
| Scope spoofing (memory sync) | `replicate` action + `scope:` resources |
| Cost attribution | budget keyed on principal, cross-node |
| Leaked grant / revocation | short TTL + registry/CRL + signature binding |
| TOCTOU | consistent grant/use-time checks |
| Path traversal | canonicalised, glob-safe path allowlists (see FS layer) |
| Least privilege default | no grant ⇒ Restricted, read-only, public scope |
| Agent misbehaviour within bounds | bounds limit blast radius; operator keeps narrow grants |

---

## 8. Phased Rollout

| Phase | Scope | Deliverable |
|---|---|---|
| 1 — Identity foundation | OIDC everywhere, loopback disabled, shared public client | consistent `user:<oidc-sub>` everywhere; fixes `local` fragmentation |
| 2 — Capability mesh | capability tokens, asymmetric keys, attenuation, evaluator, scope/replicate gating | granular authorization; fixes provenance (`originNode` = `node:<hostname>`); enables replication |
| 3 — Filesystem capability layer | per-principal path capabilities, default-deny, transaction envelope, tenant isolation | no principal has whole-FS access (see FS layer doc §14, phases P1–P5) |
| 4 — Ergonomics | declarative grants, role bundles, sharing, transparency panel | usable + enjoyable |

> The FS layer phases (P1–P5) are the detailed breakdown of phase 3 above; phase 1 (identity foundation) and phase 2 (capability mesh) are prerequisites for the FS layer's preset mapping (P2), because preset mapping keys on the authenticated `user:<oidc-sub>`.

---

## 9. Open Decisions

1. Asymmetric vs. symmetric root for operator mesh.
2. Loopback convenience vs. OIDC consistency (resolved: OIDC; revisit for headless device-flow).
3. Cost/quota calibration for family & friends.
4. Revocation propagation mechanism (CRL vs. short-TTL re-issue).
5. Strength of tenant isolation (namespace masks vs. per-tenant OS user) for `exec` grants.

---

## 10. References

- `multi-tenancy.md`, `distributed-agent-mesh.md`, `memory-architecture.md`, `formal-foundations-and-invariants.md`
- `dsh-auth/src/strategy.ts`, `dsh-auth/src/index.ts`
- `dsh-memory/src/capability.ts`, `dsh-memory/src/replication.ts`, `dsh-memory/src/index.ts`
- `filesystem-capability-layer.md` — the filesystem dimension
