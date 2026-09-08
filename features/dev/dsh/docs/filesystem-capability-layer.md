# Filesystem Capability Layer

**Status:** Design (not implemented)
**Parent:** [`mesh-capability-authorization.md`](mesh-capability-authorization.md) — granular, capability-based authorization for the distributed dsh agent mesh.
**Scope:** Extends the mesh capability model with a **filesystem capability dimension**, so that no principal (operator, tenant, agent) has access to the entire filesystem by default. Every path access is authorized per-principal, per-path-root, per-action, default-deny.

> **Honest framing.** There is no "perfect" filesystem authorization. This document specifies a *defensible* design within an explicit threat model: *principals are OIDC-attested; some may be partially untrustworthy within their grant; the OS user under which the agent runs is unprivileged; any principal granted `exec` on a node can only be constrained by OS-level confinement, not by path policy alone.* Capability semantics are the *ceiling of authority*, not a judgment of intent, and not a substitute for OS sandboxing.

---

## 1. Problem Statement

The agent runs as a single unprivileged `dsh` system user (UID 986, `CapEff: 0`). Multiple principals — the operator, family, friends, and the agent's own service scope — execute through this one OS user. Consequences:

1. **OS permissions cannot distinguish tenants.** All tenants share the `dsh` OS identity, so `chmod`/`chgrp`/ACL grants authority to *all* of them at once. Per-tenant filesystem control therefore requires a policy layer above the tools.
2. **Blanket repo access is too broad.** Granting the agent `write` to `/etc/nixos` (as done) or to a whole home directory gives it the entire tree, including unrelated files and (via traversal) sensitive ancestors.
3. **`exec` bypasses path policy.** Any principal granted shell/`exec` can read anything the OS user can read, regardless of path capabilities.

**Design premise.** "Least privilege on the filesystem" is a *two-tier* problem:

| Tier | Mechanism | What it enforces | Tenant-aware? |
|---|---|---|---|
| **OS (kernel)** — hard backstop | unprivileged `dsh` user + group/ACL ownership of granted roots | the agent process cannot cross granted roots | No (shared user) |
| **Policy (agent)** — expressive | per-principal path capabilities evaluated at every tool path access | exactly which paths each *tenant* may touch | Yes |

Both are required. OS permissions are the fallback if the policy layer is bypassed; the policy layer provides the per-principal granularity that a single OS user cannot.

---

## 2. Threat Model

- **Trusted-but-bounded principals** (operator Admin; family/friends Member/Restricted); OIDC attestation establishes *who*, not *how trustworthy*.
- The agent is **unprivileged** at the OS level; no `CAP_DAC_OVERRIDE`, no `CAP_SETUID`.
- A principal **without `exec`** is constrained by path capabilities at the tool layer.
- A principal **with `exec`** requires OS-level confinement (namespace / mount masks / per-tenant execution user) — path policy alone is insufficient (see §7).

**Assumed invariant:** *No capability grants more than its source; no principal gains a path root it was not explicitly granted; default action on any un-granted path is `deny`.*

---

## 3. Core Model

### 3.1 Path capability tuple

```
pathCapability := {
  principal : PrincipalURI          # user:<sub> | group:<g> | node:<id>
  roots     : PathRoot[]            # canonical rooted-path patterns
  actions   : PathActionSet         # subset of { read, write, mutate, exec }
  bounds    : { ttl, budgetEur, maxDepth, maxBytes? }
  attestation : SignedProof
}
```

- **`PathRoot`** is a canonical, pattern-based root: `/etc/nixos/**`, `/home/philipp/dev/projekt-a/`, `/var/lib/dsh/tenants/<tenant>/**`. Roots are always absolute, canonical, and may be a directory (recursive) or a glob.
- **`PathActionSet`** — the path-relevant subset of the **canonical verb set** (`read | list | write | mutate | exec | orchestrate | replicate`, see `mesh-capability-authorization.md` §4.2):
  - `read`  — open/read/stat a specific file.
  - `list`  — enumerate / glob a directory (distinct from `read`; not granted with `read` by default).
  - `write` — create/truncate/append within the root.
  - `mutate` — rename/delete/chmod within the root.
  - `exec`  — execute a command under this root (requires OS confinement, §7).

### 3.2 Principal→root mapping (default-deny)

Unless a principal holds a `pathCapability` that *dominates* the requested resource+action, the access is denied. Dominance is defined by a path-prefix order (see §4).

---

## 4. Path Language & Decision Procedure (the rigorous core)

The entire security value rests on **how a requested path is matched against granted roots** and **when that check happens**. This must be canonical, deterministic, and re-evaluated per access (no grant-time-only check).

### 4.1 Canonicalization (before any match)

```
canonicalize(path):
  1. resolve symlinks (E entire chain; break with ELOOP on cycles)
  2. condense "." and ".." segments after lexical passes
  3. reject paths escaping the root boundary ("/etc/../etc", absolute "..")
  4. reject NUL / control bytes; reject device nodes / FIFOs unless `exec` granted
  5. normalize case if the filesystem is case-insensitive (configurable)
```

A path that fails canonicalization is **rejected outright** (fail-closed) rather than coerced.

### 4.2 Root→pattern compile

Each `PathRoot` is compiled to a **prefix automaton** (or an anchored regex) with two predicates:
- `matches(path, root)` — path is `equal` or strictly `inside` the root.
- `isBoundary(path, root)` — the requested operation *crosses* the root (e.g. `rename` moving a path from inside a root to outside it, or a symlink whose target escapes).

Crucially, **`read`/`write`/`mutate` are authorized per path-prefix**, and **cross-boundary operations (rename/delete of a root, symlink pointing outside) are authorized by the *destination/target* root**, not the source.

### 4.3 Authorization (evaluated at access time)

```
authorise(principal, path, action, now) :=
  p  := canonicalize(path)
  ∃ cap : cap.principal dominates principal
        ∧ matches(p, cap.roots)
        ∧ action ∈ cap.actions
        ∧ within(cap.bounds, now)
        ∧ verify(cap.attestation)
        ∧ ¬revoked(cap)
```

**Dominated check** for principals: a `user:<sub>` capability dominates the same user; a `group:<g>` capability dominates if the principal is a member of `g`; a `node:<id>` capability dominates a node-asserted operation. Principals do **not** inherit capabilities from other principals (no implicit upward grant).

### 4.4 Default-deny and the boundary case

- **No matching capability ⇒ `deny`.** (Never "allow if the OS allows".)
- **Cross-root operations** (move a file out of a granted root, delete a root, create a bind mount): require a capability over the **destination root** and, for deletions, over the **parent** — the most restrictive of the two applies.

---

## 5. Per-Principal Policy Examples

| Principal | roots | actions | Notes |
|---|---|---|---|
| Operator `user:<philipp-sub>` | `/etc/nixos/**`, `/home/philipp/dev/**`, `/var/lib/dsh/tenants/<philipp>/**` | read, write, mutate, exec | full personal scope |
| Member `user:<family-sub>` | `/srv/media/**`, `/home/philipp/public/**` (read-only) | read | no config, no `dev`, no home-private |
| Restricted `user:<friend-sub>` | `/srv/public/**` | read | minimal |
| Agent service scope `node:<hostname>` | `/var/lib/dsh/tenants/<tenant>/**` + explicitly granted workspace roots | read, write, mutate | service-internal |
| Default (no grant) | — | — | `deny` |

> The column "granted workspace roots" is what the operator configures (e.g. `/etc/nixos`). Everything not listed here is out of scope for that principal, regardless of OS permissions.

---

## 6. Composition with the Mesh Capability Model

The filesystem dimension is a **resource subtype** of the mesh capability (Weg B). A node-level grant already carries `resources` and `actions`; the filesystem adds a `path:` resource class:

```
resource := node:<id> | tool:<op> | scope:<scope> | path:<PathRoot>
action   := read | list | write | mutate | exec | orchestrate | replicate   (canonical set; see mesh doc §4.2)
```

- **Mesh (outer):** `authorise(principal, node, action)` decides *which node* and *which category*.
- **Filesystem (inner):** `authorise(principal, path, action)` decides *which path* within that node.

The inner check is always evaluated; an outer grant over `node:all` with `action: mutate` still requires an inner `pathCapability` over the concrete path. **No outer grant bypasses the inner path check.**

---

## 7. The `exec` Bypass & Tenant Isolation (must be answered honestly)

Path capabilities constrain **non-`exec`** actions (read/list/write). If a principal holds `exec` on a node, the running process can read any path the OS user can read. Therefore, **`exec` authority must be coupled with OS-level confinement**, in increasing strength:

1. **Unprivileged OS user (already):** the `dsh` user has no DAC-escape capability.
2. **Per-tenant mount/namespace masks:** `unshare -m -u` (as specified in `multi-tenancy.md` §1/§3) masks `/var/lib/dsh/tenants/` and the filesystem so a tenant process only sees its own view. This is the *only* mechanism that truly isolates one tenant from another, because they otherwise share the same OS identity.
3. **Per-tenant execution identity (stronger):** a dedicated unprivileged OS user per tenant (`dsh-tenant-<u>`), so OS permissions themselves are tenant-scoped. This is stronger but adds user-management overhead.

**Recommendation:** enforce path capabilities at the tool layer for all principals, **and** enforce per-tenant namespace/mount isolation whenever `exec` is granted, so the policy is not a paper tiger for privileged tool categories. The OS backstop (unprivileged `dsh` user + granted roots) remains mandatory.

---

## 8. Interplay with the Upstream Sandbox & Permission Presets (Three Enforcement Axes)

The upstream dsh runtime already ships a sandbox stack. Understanding exactly what it does and does not confine is essential — otherwise the path-capability design either duplicates it or assumes a protection it does not provide.

### 8.1 What upstream provides

| Seam / package | Role |
|---|---|
| `ctx.sandbox` (`@deepseek-ai/dsh-sandbox`) | the process-sandbox **seam** (abstract provider) |
| `sandbox-local` (`@deepseek-ai/dsh-sandbox-local`) | **Landlock**-based local runner (default); **bwrap is a bwrap-compatible runner profile, not the default** |
| `ctx.sandboxPolicy` (`@deepseek-ai/dsh-sandbox-policy`) | single home of the deployment default `SandboxMode` (default **`read-only`**) + workspace root |
| `ctx.permissionPresets` | the user-facing preset table (**`workspace-write`**, **`danger-full-access`**, **`dangerously-bypass-approvals-and-sandbox`**) that bundles sandbox-mode **and** approval knobs |
| `fs-sandbox` / `fs-observation-policy` | fence filesystem **mutations** by the shared sandbox mode; contribute observed-state checks via the `fs/*` event gate |
| `ctx.subprocess` | spawns bash / PTY / LSP / subagent backends; consumers wrap argv before spawning |

### 8.2 The critical corrigendum

**The process sandbox confines spawned processes (`bash`/`exec`), NOT the in-process filesystem providers.**

Upstream postmortem 0002 states it plainly: *"the default ACP composition is intentionally bash-only because its sandbox cannot confine in-process filesystem providers."* The `read`/`write`/`edit` tools run **in the Host process** and are not wrapped by the process sandbox; they are fenced instead by `fs-sandbox` (sandbox *mode*) and `fs-observation-policy`. `bwrap`/Landlock therefore do **not** automatically restrict the file tools.

### 8.3 Three enforcement axes (each required; none is sufficient alone)

| Axis | Mechanism | Confines | Tenant-aware? |
|---|---|---|---|
| **1. Auth → permission preset** | LBAC clearance maps to a `permission-presets` entry (sandbox/mode + approval) | `bash`/`exec` + whole-session behaviour | Yes (per session) |
| **2. Path-capability layer** | per-principal `pathCapability` at the fs tools / `fs/*` gate | in-process `read`/`write`/`edit` | Yes (per principal) |
| **3. Tenant isolation** | `unshare -m -u` mounts per tenant | one tenant vs another sharing the OS user | Yes |

**Why "full access gated behind auth" is axis 1 only:** mapping clearance to a permission preset is a real, coherable hook (`permission-presets` writes a `permission/preset` event → sandbox-mode + approval). It correctly constrains the process sandbox and the session approval policy. But it does **not** constrain the in-process file tools (axis 2) and does **not** separate tenants sharing one OS user (axis 3).

### 8.4 Integrity requirement (single source of truth)

Upstream ensures `bash` and `fs` **read the same `sandboxPolicy`** so *"bash and fs cannot confine to different roots."* The path-capability layer must honour the same invariant: **one shared authorization primitive** consulted by every path-authoritative tool and by the exec gate. A per-tool ad-hoc check would immediately open a hole (one tool trusts a different policy than another).

### 8.5 Deployment truth

The NixOS feature wires settings/patch documents but does **not** explicitly set `sandbox-policy` or a permission preset — the session mode comes from the upstream bundle (`SandboxMode` default `read-only`); in the current eval it is elevated to `danger-full-access` (a preset, not derived from the feature config). So "full access" is already a permission preset, and gating it behind auth is: **map the authenticated tenant's clearance → preset**. That is a clean, additive integration.

---

## 9. Tool-Layer Integration

Each path-authoritative tool consults the policy at call time:

| Tool | Consults policy for | Sandbox interplay |
|---|---|---|
| `read` / `read_file` | `read` on the requested path | in-process; fenced by the path-capability layer (axis 2) |
| `write` / `edit` / `glob`? | `write` on the requested path; `glob` requires `read` (`list`) | in-process; fenced by `fs-sandbox` mode + path-capability |
| `bash` / `exec` / `exec_shell` | `exec` — AND requires process sandbox (§7, axis 1+3) | wrapped by `ctx.sandbox` |
| `git` / `nix` mutations | `mutate` on the repo root | via `ctx.subprocess` + `fs-sandbox` |
| `workspace_propose_mutation` | `write` on each staged path, within the transaction envelope (§10) | CoW overlay + 2PC |

Listing (`glob`, directory read) is **optionally** a distinct `list` action (default: not granted even with `read`), so an operator can grant read of a specific file without exposing the parent directory listing.

---

## 10. Transactional Envelope (CoW + 2PC)

Beyond per-path authorization, mutating catalogues should be **bounded by the workspace-transaction model** (see `formal-foundations-and-invariants.md` — CoW-OverlayFS OCC; `distributed-agent-mesh.md` — 2PC):

- A mutation runs on an **ephemeral CoW overlay / git worktree** of the granted repo.
- **Every path** the mutation touches must satisfy the principal's `pathCapability`; any access outside is rejected at `propose` time.
- Commit applies only if the whole transaction is within the envelope **and** the human-in-the-loop approval (if enabled) passes.

This gives **atomicity + least-privilege in one place** — a mutation cannot "escape" the granted roots half-way through.

---

## 11. Edge Cases & Countermeasures

| Edge case | Handling |
|---|---|
| **Symlink to an out-of-scope file** | canonicalize *and* verify the resolved target against `roots`; reject if target escapes. |
| **Path traversal (`../`)** | reject after canonicalization; no lexical coerce. |
| **TOCTOU (check-then-use)** | re-canonicalize at every access; bind the capability to a stable file descriptor or re-verify the resolved inode. |
| **Hard links into a granted root** | only granted if the source inode is also under a granted root (no privilege via hardlink). |
| **Case-insensitive FS** | canonicalize to the stored case; configurable per root. |
| **Bind / mount points inside a root** | treat mount roots as **new boundaries**; require explicit capability over the mounted path. |
| **Rename across a root boundary** | authorize against **destination** root (most restrictive of source/dest applies). |
| **Dynamic/unknown paths (temp, runtime)** | restrict to explicitly granted roots (e.g. `/tmp/dsh/<tenant>/**`), never ambient `/tmp`. |
| **Race on rename/delete** | serialize within the transaction envelope (2PC) so the check and the effect are atomic. |
| **Deleting a whole granted root** | require `mutate` on the **parent** too, and an explicit high-clearance grant. |
| **Grant leakage** | short TTL + revocation registry + signature binding (as in Weg B). |
| **Malformed/glob-heavy roots** | reject globs that could alias outside the intended root; use prefix automata, not regex match-everything. |
| **Sandbox-mode divergence (bash vs fs)** | both read the same policy source (§8.4); the path-capability layer enforces the same root for both. |
| **`exec` granted despite restricted preset** | block: map clearance to preset and refuse `exec` unless axis-3 isolation is active. |

---

## 12. Layered Defense & Residual Risk

| Layer | Stops |
|---|---|
| **OS backstop** (unprivileged `dsh` user + granted-root ownership) | reading/writing outside granted roots even if the policy is bypassed or the agent is misused |
| **Upstream process sandbox** (Landlock; permission preset) | `bash`/`exec` escaping granted roots / running arbitrary processes |
| **Path-capability policy** (tool layer, per principal, default-deny) | a tenant touching a path it was not granted (incl. in-process fs tools) |
| **Namespace / mount isolation** per tenant | a tenant seeing another tenant's files or the broader FS, especially under `exec` |
| **Transactional envelope** (CoW + 2PC + approval) | partial/half-way mutations escaping the granted roots |

**Residual risk (honest):**
- A principal with `exec` is the weakest link; it relies on the process sandbox *and* tenant isolation being correct, not path policy.
- The policy layer depends on **every** path-authoritative tool consulting the one shared primitive (miss one → hole).
- The process sandbox does **not** confine the in-process file tools — path-capability (axis 2) is not optional, it is the primary protection for `read`/`write`/`edit`.
- Content confidentiality is **not** addressed: a principal granted `read` on a path can read what is there, including accidentally-committed secrets. Secret hygiene remains an operator responsibility.
- Absolute granularity increases maintenance and the chance of misconfiguration; defense in depth should be prioritized over exhaustive per-file rules.

---

## 13. Declarative Config Shape (agnostic)

```nix
my.features.dev.dsh.agent.filesystem = {
  enable = true;                       # enable the policy layer
  defaultDeny = true;                  # (invariant; hard-wired, not a toggle in practice)
  tenants = {                          # per-principal path grants
    "user:<philipp-sub>" = {
      roots = [ "/etc/nixos/**" "/home/philipp/dev/**" ];
      actions = [ "read" "write" "mutate" ];
    };
    "user:<family-sub>" = {
      roots = [ "/srv/media/**" ];
      actions = [ "read" ];
    };
  };
};
```

The module:
- compiles roots to canonical prefix automata,
- injects a single shared **path-authorisation primitive** that every path tool consults,
- wires the transactional envelope to re-verify every staged path,
- maps each tenant's clearance to a **permission preset** (sandbox/mode + approval; axis 1),
- and (when `exec` is granted) enables per-tenant namespace/mount isolation (axis 3).

All of it agnostic — keyed on `user:<sub>`/`group:<g>`/`node:<id>`, path roots as raw strings, no hardcoded usernames, hostnames, or stacks.

---

## 14. Implementation Phases & Verification

| Phase | Deliverable |
|---|---|
| **P1 — Policy primitive** | canonicalizer + root automaton + `authorise()`; wire `read`/`write` tools; default-deny. Verify: deny/allow matrix + symlink/`..`/win32-case tests. |
| **P2 — Preset mapping** | map LBAC clearance → `permission-presets` (sandbox/mode + approval). Verify: restricted tenant gets `read-only` + approval; Admin preset unaffected. |
| **P3 — Transaction envelope** | CoW overlay / worktree + per-path re-check at propose; 2PC commit. Verify: cross-root mutation is rejected atomically. |
| **P4 — Tenant isolation** | `unshare -m -u` mounts per tenant when `exec` is granted. Verify: tenant A cannot read tenant B or the broader FS. |
| **P5 — Ergonomics** | declarative `tenants` grants, transparency/audit UI, bounded sharing (dsh-share). |

**Verification gates (all hosts):** `nix flake check` (eval-hosts + statix + deadnix); a permission matrix test that a denied path is refused by the tool policy regardless of OS perms; a sandbox-mode divergence test that bash and fs read the same policy; a mount-isolation test that `exec` does not escape the tenant view.

---

## 15. References

- `mesh-capability-authorization.md` — the parent capability model (resources/actions/bounds/attestation)
- `multi-tenancy.md` — LBAC lattice, hermetic storage, per-process namespace isolation (`unshare -m -u`)
- `formal-foundations-and-invariants.md` — CoW-OverlayFS OCC, risk lattices (R0–R2)
- `distributed-agent-mesh.md` — OCAP task contracts, 2PC, leases, Tailscale boundary
- upstream docs: `docs/upstream/capability-seams.md`, `docs/upstream/architecture.md`, `docs/upstream/postmortem/0002-js-expression-disabled-filesystem-tools.md`, `docs/upstream/subsystems/sandbox*`
- `dsh-auth/src/index.ts` — LBAC tool policy (coarse gate), quota enforcement
- `dsh-memory/src/capability.ts`, `replication.ts` — existing capability token + scope gating

---

*This document is a design analysis, not an implementation. It should be reviewed against the concrete tool surface (which tools carry the shared path-authorisation primitive) before code is written.*
