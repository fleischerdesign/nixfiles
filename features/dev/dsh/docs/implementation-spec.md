# Implementation Specification — Capability Mesh & Filesystem Capability Layer

**Status:** Implementation spec for a fresh implementer. **P1, P2, P3-core, P4 (cross-node user attribution incl. `PeerMeshStrategy` delegation) + the P5 (tenant-isolation) / P6 (audit) logic primitives are implemented.** P1/P2/P3/P5/P6 live in the `dsh-capability` plugin; P4's `PeerMeshStrategy` delegation flow applies in `dsh-auth/src/strategy.ts` (verify a `x-dsh-capability` → act for the USER principal, bounded; node channel retained when absent). Unit-tested against the matrix; `nix flake check` green. Remaining: the true runtime wiring/verification (P5 exec-wrapper application, P6 record emission from every `authorise()`, and a live service smoke test on a deployment host — the plugin compiles/packages/loads and all primitives are runtime-checked, but a live boot with the plugin injected still needs a privileged `nixos-rebuild switch`).
**Read before:** [`mesh-capability-authorization.md`](mesh-capability-authorization.md) (the capability model) and [`filesystem-capability-layer.md`](filesystem-capability-layer.md) (the filesystem dimension). This document ties the design to concrete code seams, resolves the open decisions, and defines the verification matrix.

---

## 📋 Handoff brief

You are implementing **granular, capability-based authorization for the dsh agent mesh** so that a trusted-but-bounded principal (operator, family, friends) can reach and steer nodes **only within an explicit, attestable, attenuable grant** — and no principal has whole-filesystem access by default.

**The 3 docs, in order:**
1. `mesh-capability-authorization.md` — the **what/why** (principals, capability tuple, cross-node attribution, open decisions).
2. `filesystem-capability-layer.md` — the **filesystem dimension** (path canonicalization, prefix match, three enforcement axes, tenant isolation).
3. this `implementation-spec.md` — the **how** (design→code mapping at §2, resolved decisions §1, verification matrix §3, phases §4).

**Start with Phase 1 (`§4 P1 — Policy primitive`):** canonicalizer + root automaton + shared `authorise()` primitive, wired into the dsh-auth `tools/pre-execute` hook + the fs event gate; default-deny.

**Definition of done per phase:** the phase's `§3` verification rows pass **and** `nix flake check` (all 5 hosts + statix + deadnix) is green. Do not mark a phase done on passing tests alone — confirm the runtime smoke test (`§0.2`) too. Build one phase, verify it, commit, then the next.

---

> **Honest framing for the implementer.** "Perfect" means *coherent within the stated threat model*, not absolute. Build in phases; every phase must pass `nix flake check` and the corresponding verification matrix. Do not claim completion on a phase whose matrix tests fail.

---

## 0. Current-State Baseline (what already exists)

The following upstream seams and plugins are present and are read, not written blindly:

| Seam / plugin | File | Role |
|---|---|---|
| `ctx.sandbox` | upstream `packages/sandbox/sandbox`, `sandbox-local`, `sandbox-policy` | process-sandbox seam; **Landlock default, bwrap preferred on Linux** (probed first) |
| `ctx.fs` / `fs-sandbox` / `fs-observation-policy` | upstream `packages/fs/*` | **in-process** filesystem providers; fenced by sandbox *mode* + `fs/*` event gate |
| `ctx.permissionPresets` | upstream `packages/interaction/permission-presets` | bundles sandbox-mode + approval knobs (`workspace-write`, `danger-full-access`, bypass) |
| `ctx.subprocess` | upstream `packages/subprocess/*` | spawns bash / PTY / LSP / subagents |
| `ctx.sandboxPolicy` | upstream `packages/sandbox/sandbox-policy` | single home of `SandboxMode` (default `read-only`) + workspace root |
| `dsh-auth` | `plugins/dsh-auth/src/strategy.ts`, `index.ts` | LBAC tool policy (`enforceLbacToolPolicy`, Admin-only set), token-bucket quota, PeerMeshStrategy (node-only HMAC), LoopbackStrategy, session cookie |
| `dsh-memory` | `plugins/dsh-memory/src/capability.ts`, `replication.ts`, `index.ts` | capability tokens, scope gating, fail-closed replication (`replicationNodeId = ... || 'local'`), `tenantContext`, HLC |

**Known defects to fix (from the design docs):**
1. `PeerMeshStrategy` returns `clearance: 'Admin'` for any node peer — no user attribution.
2. Memory `replicationNodeId` / `originNode` falls back to `'local'` (not `node:<hostname>`), colliding across nodes.
3. Loopback-based anonymous `local` (Admin) identity fragments user-scoped memory.
4. `memory.replication.enable` defaults `false` — replication not wired.

### 0.1 Codebase topography — what you can actually edit

**Critical.** The upstream seams referenced below (`ctx.sandbox`, `sandbox-local`, `fs-sandbox`, `sandbox-policy`, `permission-presets`, `subprocess`) are **NOT in this repository** — they ship inside `pkgs.custom.dsh` (built from upstream via `packages/custom/dsh`). You **do not fork or edit them here.** You wrap/configure them, or hook them, from the dsh feature layer.

**Editable here:**
- `features/dev/dsh/plugins/<name>/src/*.ts` — the dsh feature plugins: `dsh-auth`, `dsh-memory`, `dsh-mesh`, `dsh-workspace-tx`, `dsh-share`. This is where the capability token, the shared `authorise()` primitive, the LBAC/`tools/pre-execute` hook, and cross-node attribution live.
- `features/dev/dsh/default.nix` + `lib/render.nix` + `lib/runtime.nix` — the declarative NixOS/Cordis wiring (patch layer, settings, `agent.packages`/`agent.workspaces`).
- `docs/` (this family).

**Not editable (upstream, configure/wrap instead):** the process sandbox, `fs-sandbox`, `sandbox-policy`, `permission-presets`, `subprocess`. Reach their behaviour via the Cordis patch layer (`cordis.patch.yml`, rendered by `lib/render.nix`) and via the `my.features.dev.dsh.*` options.

**Consequence for the design:** the shared `authorise()` primitive and the path-capability layer are implemented **in a dsh plugin** (e.g. extend `dsh-auth`, which already intercepts `tools/pre-execute`) — **not** by modifying upstream `fs-sandbox`. You hook the fs provider group through the plugin layer's event gates, not by forking upstream code.

### 0.2 Build & verification loop

- **Plugin change** → rebuild the dsh package: `nix build .#dsh` (or `nix build .dsh`), and re-evaluate the host that uses it: `nix build .#nixosConfigurations.<host>.config.system.build.toplevel --dry-run`.
- **Smoke test** the service after a rebuild: `OUT=$(nix build .#dsh --print-out-paths --no-link | tail -1); DSH_HOME=$(mktemp -d) timeout 40 "$OUT/bin/dsh" web --no-open` (stable server = exit 124).
- **Lint gate:** `nix flake check` (all 5 hosts + statix + deadnix). `nixfmt`/`deadnix`/`statix` are only in a dev shell / the flake checks — not on a bare PATH.
- **Config test:** `nixos-rebuild switch` + `systemctl restart dsh-web` on the deployment host; verify with the V-matrix.

**Deployment specifics (already in place, from this session):** the dsh agent runs as the unprivileged `dsh` system user (no home-manager profile, shell `nologin`); each host grants itself access via `agent.workspaces` (durable oneshot: ACL traverse + group-write) and `agent.packages` (dsh-user tool set, incl. `git`/`gh`, wired to the service PATH via `makeBinPath`). The identity is `user:<oidc-sub>` (OIDC everywhere, loopback disabled).

---

## 1. Resolved Decisions

| Open decision | Resolution | Rationale |
|---|---|---|
| Attestation root of trust | **Asymmetric** keys for public/family principals; **symmetric** mesh secret for the operator-only mesh | asymmetric is the only way to *prove* who a principal is once outsiders are admitted |
| Loopback vs OIDC | **OIDC everywhere, loopback disabled** on every host; headless device-flow deferred | consistent `user:<oidc-sub>` is a correctness requirement for grants |
| Revocation | **Short TTL + re-issuance** (default 30 d per `sessionTtlDays`); optional CRL later | simpler, bounded blast radius for a homelab |
| Tenant isolation for `exec` | **Namespace/mount masks** (`unshare -m -u`) per tenant (primary); per-tenant OS user as a later, stronger option | path policy alone cannot confine an executor process |
| Quota calibration | Keep upstream `DEFAULT_CAPS`: Member 15 €/30 d, Restricted 5 €/30 d, Admin unbounded | reuse existing token-bucket default; keyed on principal |

---

## 2. Design → Code Mapping

### 2.1 Capability token (extend, don't fork)
**File:** `plugins/dsh-memory/src/capability.ts` (and types in `mesh-capability-authorization.md` §4).
Add to the existing token: `principal`, `resources` (incl. `path:` class), `actions`, `bounds { ttl, budgetEur, maxTurns, maxDepth, pathAllowlist[], resourceAllowlist[] }`. Keep the existing `iss`/`sub`/`sink` fields; `sink` binds a token to the initiating node (non-replay).

### 2.2 Shared authorization primitive (the one source of truth)
**New:** a single `authorise(principal, resource, action, now)` primitive used by *every* path-authoritative tool and the exec gate.
**Wire into:**
- `tools/pre-execute` (LBAC coarse gate — see `dsh-auth/src/index.ts` `enforceLbacToolPolicy`), for the coarse clearance check;
- the `fs/*` event gate + `fs-sandbox` (upstream `packages/fs/*`), for in-process `read`/`write`/`edit`;
- `ctx.subprocess` consumers (bash/exec) for spawn-time path confinement.

**Invariant (mandatory):** one primitive; bash and fs must read the same policy so they cannot "confine to different roots" (upstream `sandboxPolicy` already demands this).

### 2.3 Cross-node principal attribution
**File:** `plugins/dsh-auth/src/strategy.ts` (`PeerMeshStrategy`).
- Keep the node HMAC (transport channel).
- A cross-node call must additionally carry a **delegation capability** whose `principal = user:<oidc-sub>` and whose `sink = <initiating node>`.
- The target evaluates the **user** capability (not the node) — see `mesh-capability-authorization.md` §4.5. Never authorize a cross-node call on the node HMAC alone (that is the current peer⇒Admin hole).

### 2.4 Path capability layer
**Files:** analogous to the FS doc §4 (canonicalizer + prefix automaton) + §9 (tool integration). Not present upstream — this is new.
- Canonicalize (resolve symlinks, reject `..`, NUL, device nodes).
- Match each requested path by **prefix automaton** (not exact URI).
- Evaluate at access time (no grant-time-only check); default-deny.
- Wire into `read`/`write`/`edit`/`bash`(exec)/`glob`(list) tools.

### 2.5 Tenant isolation
**Files:** `multi-tenancy.md` §3 (namespace synthesis) + `fs-capability-layer.md` §7.
- When a principal holds `exec`/`run`, run its tools under `unshare -m -u` masks so one tenant cannot see another's files or the broader FS.
- The upstream process sandbox (Landlock/bwrap) confines *spawned* processes but does **not** separate one tenant from another within the shared OS user.

### 2.6 Deployment wiring (already partly done)
The NixOS feature already has: `agent.packages` (dsh-user tool set), `agent.workspaces` (durable OS backstop: ACL traverse + group-write), and the dsh-web service PATH. The capability layer must **sit above** this OS backstop as the *logical* per-principal gate (see `fs-capability-layer.md` §1 two-tier premise).

---

## 3. Verification Matrix

Each phase must pass the applicable rows (expected = the reference outcome the design mandates).

| # | Case | Action | Expected |
|---|---|---|---|
| V1 | default-deny | a principal with no grant touches any path | `deny` (no OS fallback) |
| V2 | granted read | `user:<sub>` `read` on a granted file | `allow` |
| V3 | granted write | `user:<sub>` `write` on a granted root | `allow` |
| V4 | un-granted sibling | write to an un-granted path next to a granted one | `deny` |
| V5 | symlink escape | `read` a symlink resolving outside the granted root | `deny` |
| V6 | `..` traversal | `read /granted/../outside` | `deny` |
| V7 | rename across boundary | `rename` a file from inside a granted root to outside | `deny` (authorise against destination root) |
| V8 | delete a whole granted root | `mutate` the root itself | `deny` unless parent + high-clearance grant |
| V9 | cross-tenant read | tenant A reads tenant B's path | `deny` |
| V10 | scope spoofing (memory) | a foreign `user:x` fact pushed as `user:philipp` | `deny` (via `replicate` + `scope:` resource) |
| V11 | `exec` bypass | a principal with `read`-only tries `exec` | `deny`; and if granted `exec`, tenant isolation is active |
| V12 | escalation (non-widening) | a delegated capability attempts to widen its parent | `deny` |
| V13 | replay | a captured token is replayed after TTL/nonce | `deny` |
| V14 | node-channel vs user | a cross-node call authenticated as node but granting as user | only the user capability is evaluated; node HMAC is the channel only |
| V15 | bash/fs divergence | bash and fs read different policy roots | treated as a failure (single source of truth) |

**Gate:** `nix flake check` (all 5 hosts + statix + deadnix) passes on every committed phase; the matrix rows for that phase pass.

---

## 4. Phased Plan & Gates

| Phase | Deliverable | Gate |
|---|---|---|
| **P1 — Policy primitive** | canonicalizer + root automaton + `authorise()`; wire `read`/`write`; default-deny | V1–V7, V15 |
| **P2 — Preset mapping** | LBAC clearance → `permission-presets` (sandbox/mode + approval) | V11; `User` (restricted) gets `read-only` + approval |
| **P3 — Capability tokens** | extend `capability.ts` (principal/resources/actions/bounds); attenuation; revocation | V12, V13 |
| **P4 — Cross-node attribution** | `PeerMeshStrategy` user-principal delegation; target evaluates user capability | V14; fixes origin `'local'` → `node:<hostname>` |
| **P5 — Tenant isolation** | `unshare -m -u` per tenant when `exec` granted | V9, V11 (isolation active) |
| **P6 — Ergonomics** | declarative grants, role bundles, bounded sharing, audit/transparency UI | usability + audit present |

---

## 5. Implementation Truths (do not skip)

1. The upstream **process sandbox does not confine the in-process fs tools.** Path-capability (P1) is the **primary** protection for `read`/`write`/`edit`, not optional.
2. `exec`/`run` authority requires **OS-level confinement**, not merely path policy — otherwise it's a paper tiger.
3. The **one shared primitive** is non-negotiable; a tool that reads a different policy is a hole.
4. Content **confidentiality** is out of scope — a `read` grant exposes what is readable. Secret hygiene is the operator's responsibility.
5. Memory provenance must use the **mesh node id** (`node:<hostname>`), never `'local'`.
6. The identity is **`user:<oidc-sub>`** everywhere (OIDC, loopback off); do not reintroduce a loopback-anonymous path.
7. Keep everything **agnostic** — no hardcoded usernames, hostnames, or team names in the model (feature invariant); keys are URIs (`user:*`, `group:*`, `node:*`, `tool:*`, `scope:*`, `path:*`).

---

## 6. References

- `mesh-capability-authorization.md` — capability model (resources/actions/bounds/attestation, cross-node attribution §4.5)
- `filesystem-capability-layer.md` — path canonicalization, prefix match, tenant isolation, two-tier premise, upstream-sandbox interplay (§8)
- `multi-tenancy.md` — LBAC lattice, hermetic storage, `unshare -m -u`
- `distributed-agent-mesh.md` — OCAP contracts, 2PC, leases, DAG guard
- `formal-foundations-and-invariants.md` — CoW-OverlayFS OCC, risk lattices
- upstream docs: `docs/upstream/capability-seams.md`, `architecture.md`, `subsystems/sandbox*`, `postmortem/0002-js-expression-disabled-filesystem-tools.md`
- `dsh-auth/src/strategy.ts`, `index.ts`; `dsh-memory/src/capability.ts`, `replication.ts`, `index.ts`

---

*This is an implementation spec; build in phases and let `nix flake check` + the matrix be the definition of done per phase.*
