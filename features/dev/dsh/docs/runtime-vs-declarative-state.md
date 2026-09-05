# Runtime Autonomy vs. Declarative Policy (The Dual-State Coherence Model)

Formal reconciliation architecture between immutable, declarative system configurations (NixOS / GitOps) and autonomous, mutating agent runtimes (Cordis actors, scheduled jobs, webhooks, memory).

---

## 1. The Fundamental Dilemma: Two Realities

Modern autonomous agents require runtime adaptability (creating timers, subscribing to webhooks, storing long-term memories). Conversely, NixOS demands total determinism and hermetic idempotency.

Naive implementations collapse into one of two failure modes:
1. **The Amnesia Trap:** Runtime creations are stored in locations purged or overwritten during a `nixos-rebuild switch`.
2. **The Entropie Drift:** The agent mutates the system state untracked, degrading the reproducibility of the Git-backed configuration.

To eliminate both traps, DSH formalizes the **Dual-State Coherence Model**:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                 TIER 1: DECLARATIVE POLICY (NixOS / GitOps)                 │
│         "What CAN exist? What safety envelopes and bounds are enforced?"    │
│                                                                             │
│   - Daemons, sockets, ports, and external network ingress routes            │
│   - Hard execution constraints (maxActiveJobs, minInterval, rateLimits)     │
│   - Cryptographic secrets, capabilities, and tenant identity bindings       │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │ Enforces Invariants & Quotas (Static Policy)
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                 TIER 2: AUTONOMOUS RUNTIME STATE (Dynamic Store)            │
│         "What did the agent or user dynamically request at runtime?"        │
│                                                                             │
│   - Ephemeral / scheduled jobs (stored in durable SQLite state directories) │
│   - Ingress event handler dispatch tables                                   │
│   - Semantic vector embeddings (hierarchical tenant knowledge graphs)       │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │ Optional Promotion (Human-in-the-Loop)
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                  TIER 3: DECLARATIVE PROMOTION (GitOps Feedback)            │
│         "Elevating proven runtime workflows to permanent infrastructure"    │
│                                                                             │
│   - Agent proposes verified automation as a declarative .nix commit         │
│   - Eliminates volatile runtime overhead once a pattern is mature           │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Policy-State Separation Matrix

Every dynamic capability is classified into its strictly bounded operational boundary:

| Subsystem | Declarative Authority (Nix) | Runtime Authority (Agent) | Storage Boundary | Invariant Guarantee |
|---|---|---|---|---|
| **Cron / Timers** | Scheduler daemon, execution timeout, minimum interval, tenant quotas | Creating, pausing, modifying scheduled user tasks | Durable SQLite in `/var/lib/dsh/tenants/<u>/scheduler.db` | $\text{interval} \ge 300\,\text{s}$, $\text{activeJobs} \le 10$, $\text{ttl} \le 90\,\text{d}$ |
| **Webhooks (Ingress)** | Listening ports, Caddy TLS termination, HMAC secrets | Registering turn handlers for specific incoming event payloads | In-memory / SQLite routing table | No dynamic port binds; unknown events yield immediate `204 No Content` |
| **Vector Memory** | Engine runtime (`sqlite-vec`), embedding models, storage quotas | Storing, querying, and updating conversation memories | `/var/lib/dsh/tenants/<u>/vectors.db` | Hermetic tenant namespaces, filtered retrieval across lattice boundaries |
| **Execution Sandbox** | Linux cgroup parameters, `nix-shell` package cache policies | Invoking hermetic tools and ephemeral packages | Ephemeral Linux mount namespaces (`/tmp/`) | Strict process tree SIGKILL upon timeout; zero mutation of host `/nix/store` |

---

## 3. Mathematical Formalization of Runtime Safety Envelopes

Let $\mathcal{J}$ be the set of all active runtime scheduled tasks for tenant $u$. Every runtime creation request is evaluated by the Cordis kernel against the static safety envelope $\mathcal{E}$:

$$\mathcal{E} = \langle \Delta t_{\text{min}}, K_{\text{max}}, T_{\text{ttl}} \rangle$$

A proposed scheduled task $j = \langle \text{cronExpr}, \text{action}, \text{createdAt} \rangle$ is admitted if and only if:

$$|\mathcal{J}_u| < K_{\text{max}} \quad \land \quad \text{minPeriod}(j.\text{cronExpr}) \ge \Delta t_{\text{min}}$$

where:
- $K_{\text{max}} \in \mathbb{N}$ is the tenant's hard active job limit (e.g. 10).
- $\Delta t_{\text{min}} \in \mathbb{R}^+$ is the minimum allowed periodicity (e.g. 300 seconds), preventing tight-loop denial of service.

### 3.1 Automatic State Eviction & Expiration
Every runtime-created job carries an absolute lifespan limit:
$$\text{expiresAt}(j) = j.\text{createdAt} + T_{\text{ttl}}$$
Jobs exceeding $T_{\text{ttl}}$ without user re-affirmation are garbage-collected automatically to prevent dormant process accumulation.

---

## 4. The Promotion Loop: From Runtime Experiment to GitOps Fact

When a dynamic runtime workflow (e.g. a scheduled daily report or custom data processing script) proves valuable and stable over time, DSH can trigger the **Declarative Promotion Protocol**:

1. **Telemetry & Verification:** The task executes successfully for $N \ge 14$ consecutive days with zero aborts ($\Phi = \text{true}$).
2. **Synthesis:** The agent synthesizes an equivalent declarative NixOS module (e.g. in `features/services/home-assistant/` or `roles/pc.nix`).
3. **Admin Review:** DSH presents the diff in the WebUI to the administrator:
   > *"The runtime briefing job has run reliably for 14 days. Would you like to promote it to a permanent NixOS timer via a Git commit?"*
4. **Clean Cutover:** Upon administrative confirmation, the Git commit is applied and the runtime job in `scheduler.db` is atomically decommissioned, closing the loop without state duplication.
