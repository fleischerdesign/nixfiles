# Distributed Agent Mesh & Hermes-DSH Integration Architecture

Formal system architecture, transaction semantics, failure models, and protocol specification for the distributed agent federation across NixOS nodes (Hermes Cognitive Orchestrator ↔ DSH Execution Mesh).

---

## 1. System Overview & Core Philosophy

The distributed agent architecture federates the cognitive orchestration layer (**Hermes**, running as an executive agent with WebUI) with distributed execution runtimes (**DeepSeek Harness / dsh**, powered by Cordis actors) across the private Tailscale network.

Rather than exposing unconstrained shell access or arbitrary ad-hoc chat channels, the integration strictly adheres to:
1. **The Object-Capability (OCAP) Model**: Operations require explicit, bounded, unforgeable capability tokens.
2. **Contract-Driven Delegation**: Interactions are structured as formal Task Contracts with mathematical preconditions and postconditions.
3. **Transactional File System Semantics**: All mutating tasks execute in ephemeral Git worktrees with Two-Phase Commit (2PC) guarantees.
4. **Partition-Tolerant Leases**: Fail-closed execution prevents orphaned runs (zombie agents) and token exhaustion during network partitions.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       HERMES COGNITIVE ORCHESTRATOR                         │
│                  (State Machine: S_Hermes | Interface: WebUI)               │
│                                                                             │
│   WebUI Prompt ──► Plan / Decompose ──► Task Contract C = ⟨I,P,G,R,Φ⟩       │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
                                       │ ACP (Agent Client Protocol) / JSON-RPC 2.0
                                       │ Tailscale WireGuard Transport (mTLS / WireGuard)
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                        DSH DISTRIBUTED EXECUTION RUNTIME                    │
│                            (Cordis Kernel & Actor)                          │
│                                                                             │
│   Capability Check ──► Lease & Watchdog ──► Sandboxed Worktree Execution    │
│                                       │                                     │
│                                       ▼                                     │
│                            Atomic Two-Phase Commit                          │
│                        (Merge on Φ or Clean Rollback)                       │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Mathematical Formalization: The Task Contract

Every cross-node delegated turn is formalized as a contract tuple:

$$\mathcal{C} = \langle \mathcal{I}, \mathcal{P}, \mathcal{G}, \mathcal{R}, \Phi \rangle$$

### 2.1 Identity & Attribution ($\mathcal{I}$)
- $\text{TaskUUID} \in \{0,1\}^{128}$: Globally unique task identifier.
- $\text{ParentSessionID}$: Session identifier of the initiating actor in Hermes.
- $\text{OriginNode} \in \text{Topology}$: Host identifier of the delegating node (e.g. `rollins`).
- $\text{TargetNode} \in \text{Topology}$: Host identifier of the target worker (e.g. `jello`).
- $\vec{L} = [n_1, n_2, \dots, n_m]$: Lineage vector of all ancestral nodes in the delegation chain.

### 2.2 Preconditions ($\mathcal{P}$)
Before accepting execution, the target worker verifies the exact local state:
- $\text{BaseCommit} = \text{git rev-parse HEAD}$ on target repository.
- Worker rejects the contract immediately if $\text{WorkspaceState} \ne \text{clean}$ or if $\text{BaseCommit} \ne \mathcal{P}.\text{expectedCommit}$.

### 2.3 Guardrails & Budgets ($\mathcal{G}$)
- $\text{Depth}_{\text{max}} \in \mathbb{N}$: Hard ceiling on delegation recursion depth.
- $\text{TTL}_{\text{lease}} \in \mathbb{R}^+$: Maximum execution time window before lease expiration (seconds).
- $\text{Budget}_{\text{tokens}} \in \mathbb{N}$: Maximum cumulative LLM tokens (prompt + completion) permitted for this task.
- $\text{MaxTurns} \in \mathbb{N}$: Maximum agent self-correction steps (typically $k \le 5$).

### 2.4 Resource & Capability Matrix ($\mathcal{R}$)
Fine-grained capabilities following OCAP principles:
- Allowed paths: `["/etc/nixos/**"]`
- Prohibited paths: `["/etc/nixos/secrets/**", "~/.ssh/**", "~/.gnupg/**"]`
- Tools whitelist: `["read_file", "write_file", "git_status", "nix_eval", "nix_fmt"]`
- Raw shell execution (`exec_bash`) is strictly disabled or locked inside unprivileged Linux namespaces.

### 2.5 Invariants & Postconditions ($\Phi$)
The formal proof required for a task to be marked successful:

$$\Phi = \text{nixfmt}(F) \land \text{statix}(F) \land \text{deadnix}(F) \land \big(\text{eval}(host) = \text{true}\big)$$

where $F$ is the set of files modified by the task.

---

## 3. Transactional Two-Phase Worktree Commit (2PC)

To eliminate broken intermediate states (dirty trees) and race conditions across the network, all mutations follow strict transactional isolation:

### Phase 1: Prepare & Isolate
1. **Ephemeral Worktree Allocation:**
   Upon task admission, DSH provisions an ephemeral Git worktree:
   $$\text{Path}_{\text{worktree}} = \texttt{/tmp/dsh-worktrees/} \parallel \text{TaskUUID}$$
   attached to a detached transient branch: `transient/task-<uuid>`.
2. **Hermetic Step Execution:**
   All edits, AST transformations, and evaluation checks operate exclusively inside $\text{Path}_{\text{worktree}}$. The host's primary repository (`/etc/nixos`) remains unmodified.
3. **Verification Evaluation:**
   DSH evaluates postcondition $\Phi$. If errors occur, the agent has $\le \text{MaxTurns}$ to fix them. If $\Phi$ is not satisfied, an abort is issued.

### Phase 2: Commit or Rollback
* **Rollback ($\neg \Phi$):**
  The temporary worktree is unmounted and purged (`git worktree remove --force`). The transient branch is deleted. The repository state $S_{t+1}$ is proven identical to $S_t$:
  $$S_{t+1} \equiv S_t$$
* **Commit ($\Phi$):**
  Upon verified satisfaction of $\Phi$, DSH generates a clean unified Git patch:
  $$\text{Patch} = \text{git diff } \text{HEAD} \dots \text{transient/task-<uuid>}$$
  The patch is returned to the orchestrator as a verified artifact, or merged fast-forward if auto-apply is authorized.

---

## 4. Fault Tolerance & Distributed Lifecycle

### 4.1 Lease & Heartbeat Protocol
```
Hermes (Orchestrator)                        DSH Worker (Node)
       │                                             │
       │─── ACP: task/start (Contract C, Lease=30s) ─►│ Provision Worktree
       │                                             │ Start Execution
       │◄── ACP: stream/turn (Delta, Heartbeat) ─────│ (t = 5s)
       │◄── ACP: stream/turn (Delta, Heartbeat) ─────│ (t = 10s)
       │                                             │
       X [Network Partition / Laptop Suspended]      │
       │                                             │ (t = 30s)
       │                                             │ Lease Watchdog Fires!
       │                                             │ SIGKILL child processes
       │                                             │ Purge transient worktree
       │                                             │ Fail-Closed (Zero Leaks)
```

1. **Lease Renewal:** Every streaming delta acts as a heartbeat. If execution continues without streaming tokens (e.g. long compilation), DSH emits a ping every $5\,\text{s}$.
2. **Worker Watchdog (Fail-Closed):** If no acknowledgment is received for $2 \times \text{TTL}_{\text{heartbeat}}$, DSH cancels the task context (`AbortSignal.abort('LEASE_EXPIRED')`), kills background subtasks via process-group signals, and purges the worktree.
3. **Idempotent Resumption:** Hermes stores the task UUID in its persistent session state. On reconnect, Hermes queries `task/status(uuid)` before attempting any retry.

### 4.2 Cycle Prevention in Delegation Graphs (DAG Guarantee)
To prevent infinite delegation loops ($A \to B \to C \to A$):
- Before dispatching a sub-contract to Node $Y$, Node $X$ verifies:
  $$Y \notin \vec{L} \quad \land \quad |\vec{L}| < \text{Depth}_{\text{max}}$$
- If $Y \in \vec{L}$, the dispatch is rejected at compile/eval time with `SubagentError('CYCLIC_DELEGATION_PROHIBITED')` without network transmission.

---

## 5. Security & Boundary Architecture

1. **Transport Layer:**
   Communication occurs strictly over Tailscale WireGuard endpoints (`100.64.0.0/10`). Unauthenticated public Internet exposure is impossible.
2. **Process Privileges:**
   DSH execution nodes run under an unprivileged user context. Root-level operations are exclusively performed through the `nix-daemon` socket, which enforces sandboxing.
3. **Secret Isolation:**
   Decrypted secrets (`/run/secrets/`) are shielded from child process visibility via environment scrubbing. Only credential references (`apiKeyEnv`) pass through the boundary.

---

## 6. Convergence: Hermes Sunset & DSH Unification Strategy

Rather than maintaining two divergent agent stacks (Python-monolith Hermes vs. TypeScript-modular DSH), the long-term architecture converges entirely on DSH as the unified personal and system agent.

### 6.1 Capability Migration Matrix (Hermes ➔ DSH)

| Hermes Component | Hermes Architecture | DSH Native Replacement | Migration Mechanism |
|---|---|---|---|
| **Identity & Soul** | `SOUL.md` injected once on boot | `dsh.persona` / `AGENTS.md` | Declarative persona section in Cordis runtime. |
| **Long-Term Memory** | `mnemosyne` Python package (SQLite) | `session-query-sqlite` + `@deepseek-ai/dsh-client-ui-skill` | In-tree SQLite session search + durable skill files. |
| **Integration Skills** | Custom Python scripts (HASS, Paperless, Vikunja) | **Native Skills & Tools** | Standardized DSH skills / Cordis tool plugins or unprivileged HTTP endpoints. |
| **Web Search** | `ddgs` (DuckDuckGo Python wrapper) | Web search skill / MCP tool | Reusable MCP server or dedicated web search skill. |
| **Web Interface** | `hermes-webui` React gateway | **`dsh-web` Frontend** | Native Cordis Web UI with turn rails, lineage visualization, and tool cards. |
| **Authentication** | Authentik OIDC direct in WebUI | **Caddy Forward-Auth / Proxy-Outpost** | Caddy reverse-proxy handling Authentik OIDC headers before hitting `dsh-web`. |
| **Subdomain** | `moebius.rls.ancoris.ovh` | `moebius.rls.ancoris.ovh` | Caddy route target updated from Hermes port (8644) to `dsh-web` (3080). |

### 6.2 The Skill Porting Model
Hermes integrations (Home Assistant, Paperless, Vikunja) are primarily API-driven skill prompts and helper scripts, not complex daemons:
1. **DSH Skill Representation:** In DSH, skills are modular prompt-and-instruction units (`ui-skill`) or Cordis tool plugins.
2. **Network Locality:** DSH instances on any node can reach Home Assistant (`https://hass.fls.ancoris.ovh`) and Paperless (`https://paperless.fls.ancoris.ovh`) transparently via Tailscale / Caddy internal domains.
3. **No Python Dependency Burden:** Eliminates Python 3.14 upstream patches, `pip`/virtualenv impedance mismatches, and native wheel compilation issues.

---

---

## 7. Multi-Tenancy & Family Access (MTAA)

To securely support family and multi-user deployments without cross-tenant data leaks, privilege escalation, or unbounded resource exhaustion, DSH implements a dedicated Multi-Tenant Agent Architecture (MTAA).

The complete mathematical specification, Lattice-Based Access Control (LBAC) model, Linux namespace isolation (`unshare -m -u`), and token-bucket budget enforcement are detailed in:
👉 [`docs/multi-tenancy.md`](multi-tenancy.md)

---

## 8. Implementation Roadmap

| Phase | Milestone | Deliverables |
|---|---|---|
| **Phase 1** | **Local ACP Provider** | Package `@deepseek-ai/dsh-acp` enabled via `my.features.dev.dsh.acp`, exposing stdio JSON-RPC. |
| **Phase 2** | **Tailscale Stream Transport** | Secure SSE/HTTP-2 transport over Tailscale IPs with token authorization and lease timeouts. |
| **Phase 3** | **Peer-to-Peer Remote Tools** | Cross-node tool invocation via `streamable-http` MCP bindings between nodes. |
| **Phase 4** | **Transactional Worktree Driver** | Automated `/tmp/dsh-worktrees/` lifecycle hook with atomic 2PC verification ($\Phi$). |
| **Phase 5** | **Multi-Tenant Gateway Router** | Process-level tenant isolation, LBAC lattice enforcement, and token-bucket budget caps (`docs/multi-tenancy.md`). |
| **Phase 6** | **Hermes Skill Porting** | Port HASS, Paperless, Vikunja, and Obsidian skills into DSH native skills / plugins. |
| **Phase 7** | **Moebius Ingress Cutover** | Bind multi-tenant `dsh-web` on `rollins` behind Caddy + Authentik OIDC; retire `features/services/hermes`. |



