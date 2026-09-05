# Multi-Tenant Agent Architecture (MTAA)

Formal security model, tenant isolation semantics, access lattices, and quota enforcement for multi-user and family deployments of DeepSeek Harness (DSH).

---

## 1. Threat Model & Architectural Invariants

Standard single-user coding agents assume full authority over their process and local storage. When deploying DSH as a shared family or team assistant behind an identity gateway, this assumption collapses.

MTAA addresses three specific vulnerability classes:
1. **Header Forgery & Cross-Tenant Impersonation:**
   Plaintext ingress headers (e.g. `X-Forwarded-User`) are unauthenticated inside the internal network. In MTAA, the ingress proxy passes an **asymmetrically signed JWT (Ed25519)** minted by the identity provider (Authentik). The Tenant Gateway Router (TGR) validates the cryptographic signature against the IdP's JWKS before admitting any turn.
2. **In-Process State Leaks & Prototype Pollution:**
   Running multiple tenants concurrently inside a single Node.js runtime creates severe isolation risks (V8 heap inspections, prototype pollution, shared module singletons). MTAA enforces **Process-Level Confinement**: each active tenant turn executes in an ephemeral, unprivileged worker process wrapped in Linux namespaces (`unshare -m -u`).
3. **Cross-Tenant Storage Visibility:**
   No tenant must ever be able to read, write, or enumerate the sessions, workspaces, or preferences of another tenant.

```
                       [ Untrusted Public Ingress ]
                                    │
                                    ▼
       ┌─────────────────────────────────────────────────────────┐
       │   OIDC Identity Assertion Authority (Authentik / IdP)   │
       │           JWT Signature Validation & Claims Extraction  │
       └────────────────────────────┬────────────────────────────┘
                                    │
                       Mutual TLS / Cryptographic Token
                                    │
                                    ▼
       ┌─────────────────────────────────────────────────────────┐
       │         DSH MULTI-TENANT GATEWAY ROUTER (TGR)           │
       │                                                         │
       │   1. Cryptographic Authentication Proof (Ed25519)       │
       │   2. Process-Level Namespace Synthesis (unshare -m -u)  │
       │   3. Lattice-Based Access Control (LBAC Dominance)      │
       │   4. Deterministic Leaky-Bucket Rate Limiter (Quota)    │
       └────────────────────────────┬────────────────────────────┘
                                    │
          ┌─────────────────────────┼─────────────────────────┐
          ▼                         ▼                         ▼
┌───────────────────┐     ┌───────────────────┐     ┌───────────────────┐
│ Tenant Runtime T₁ │     │ Tenant Runtime T₂ │     │ Tenant Runtime T₃ │
│  (Role: Admin)    │     │  (Role: Member)   │     │ (Role: Restricted)│
├───────────────────┤     ├───────────────────┤     ├───────────────────┤
│ FS: Mount NS      │     │ FS: Mount NS      │     │ FS: Mount NS      │
│ IPC: Isolated IPC │     │ IPC: Isolated IPC │     │ IPC: Isolated IPC │
│ Cordis: Admin-Set │     │ Cordis: Safe-Set  │     │ Cordis: Pure-Chat │
│ Quota: Unbounded  │     │ Quota: C_max = 15€│     │ Quota: C_max = 5€ │
└───────────────────┘     └───────────────────┘     └───────────────────┘
```

---

## 2. Lattice-Based Access Control (LBAC)

To formally guarantee that non-administrative family members cannot invoke destructive tools (shell commands, Git mutations, NixOS builds), permissions are modeled as a **complete security lattice** $(\mathcal{R}, \le)$:

$$\mathcal{R} = \{ \text{Restricted}, \text{Member}, \text{Admin} \} \quad \text{with} \quad \text{Restricted} < \text{Member} < \text{Admin}$$

### 2.1 Capability Classification
Every tool primitive $t \in \mathcal{T}$ carries a fixed security label $\lambda(t) \in \mathcal{R}$:

- **$\mathcal{T}_{\text{Restricted}}$ ($\lambda \le \text{Restricted}$):**
  $\{\text{search\_web}, \text{calculator}, \text{read\_own\_workspace}, \text{summarize}\}$
- **$\mathcal{T}_{\text{Member}}$ ($\lambda \le \text{Member}$):**
  $\mathcal{T}_{\text{Restricted}} \cup \{\text{hass\_control}, \text{paperless\_query}, \text{browser\_sandbox}, \text{vikunja\_tasks}\}$
- **$\mathcal{T}_{\text{Admin}}$ ($\lambda \le \text{Admin}$):**
  $\mathcal{T}_{\text{Member}} \cup \{\text{exec\_shell}, \text{git\_mutate}, \text{nix\_rebuild}, \text{cluster\_orchestrate}, \text{secret\_access}\}$

### 2.2 Confinement Theorem
An agent executing on behalf of tenant $u$ with clearance level $\sigma(u) \in \mathcal{R}$ is admitted to execute tool $t$ if and only if:

$$\lambda(t) \le \sigma(u)$$

*Proof of Non-Escalation:*
Because the relation $\le$ is transitive and the classification mapping $\lambda: \mathcal{T} \to \mathcal{R}$ is verified strictly by the Cordis kernel before tool dispatch, no composition or chain of tool calls initiated with clearance $\sigma(u) < \text{Admin}$ can access an element of $\mathcal{T}_{\text{Admin}}$.

---

## 3. Hermetic Storage & Zero-Knowledge Invariant

Each tenant $u$ is mapped to an isolated storage descriptor:

$$\mathcal{S}_u = \langle \text{HomePath}_u, \text{Database}_u \rangle$$

1. **Filesystem Isolation:**
   $$\text{HomePath}_u = \texttt{/var/lib/dsh/tenants/} \parallel u$$
   - Directory permissions are set to `0700`, owned by an unprivileged system user (`dsh-tenant-<u>:nogroup`).
   - Using Linux mount namespaces (`unshare -m`), the parent tenant directory `/var/lib/dsh/tenants/` is masked (`MS_REC | MS_PRIVATE`), rendering other tenants invisible at the VFS level.
2. **Database Isolation:**
   $$\text{Database}_u = \text{HomePath}_u \parallel \texttt{/sessions.db}$$
   - SQLite session tracing, full-text search indices, and user-defined skills reside exclusively in $\text{Database}_u$.
   - No shared database schema, cross-tenant tables, or shared connection pools exist.

---

## 4. Quota- & Budget-Enforcement (Token-Bucket Theory)

To protect the deployment from runaway agent loops and unintended API expenditures, tenant consumption follows the **Leaky Token-Bucket algorithm**:

$$B_u(t) = \min\big(C_{\text{max}}, B_u(t_0) + \rho \cdot (t - t_0)\big) - \sum_{i} \text{Cost}(turn_i)$$

where:
- $C_{\text{max}} \in \mathbb{R}^+$ is the hard monthly spending ceiling (in EUR/USD).
- $\rho$ is the refill rate (typically periodic monthly replenishment).
- $\text{Cost}(turn_i)$ is the exact cost evaluated via `dsh-cost-meter`:
  $$\text{Cost}(turn_i) = p_{\text{prompt}} \cdot N_{\text{prompt}} + p_{\text{completion}} \cdot N_{\text{completion}}$$

### 4.1 Fail-Closed Invariant
Before dispatching a prompt to any upstream LLM adapter, the Cordis kernel checks:

$$B_u(t) - \text{Cost}_{\text{worst-case}} \ge 0$$

If $B_u(t) < 0$, the request is terminated with `BudgetExceededException` **before** opening a network connection to the model provider.
