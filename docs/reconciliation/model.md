# The model

> Normative for the vocabulary and the invariants. Other documents in this package reference **R1..Rn**
> and **D1..Dn**; they are stated here once and nowhere else.

## 1. Layers (pace) and planes (concern)

The system is described on two orthogonal axes. The **layers** are a pace ranking: a lower layer changes
more slowly than the one above it, and no layer may depend upward. The **planes** are cross-cutting
concerns; a layer touches a plane only through a contract, never ad hoc.

```
   fast  ┌────────────────────────────────────────────────────────────────────┐
    ▲    │ L6  Workloads     instances: declared and ephemeral                 │
    │    │ L5  Service       my.contracts.provides.<svc>: what a service offers│
    │    │ L4  Runtime       workload placement: systemd | oci | k3s | microvm  │
    │    │ L3  Platform      data primitives, identity core, mesh ingress       │
    │    │ L2  Foundation    NixOS base: systemd, users, firewall, mesh          │
    │    │ L1  Site          inventory: subnets, hosts, devices, trust          │
   slow  │ L0  Hardware      boot, disk, kernel                                  │
         └────────────────────────────────────────────────────────────────────┘

   planes  Exposure · Identity · State · Telemetry · Backup · Secrets · Naming
```

| Layer | Changes | Contract to the layer below |
|---|---|---|
| L0 Hardware | years | - |
| L1 Site | years | `my.topology` |
| L2 Foundation | months | network and security primitives |
| L3 Platform | months | `provides`/`consumes` primitives |
| L4 Runtime | weeks | workload backend interface |
| L5 Service | weeks | contract projections |
| L6 Workloads | minutes-days | consumers |

## 2. Three state classes

Every fact in the system belongs to exactly one class.

| Class | Home | Owner | Written by | Change |
|---|---|---|---|---|
| **Declared** | Git + Nix, pure | repository | a commit | per commit |
| **Observed** | the runtime | the system that produced it | the runtime (imported, never overwritten) | per event |
| **Derived** | computed | the reconciler | a pure function of the two above | per reconcile |

`Derived = f(Declared, Observed)`. This is invariant **R6**.

## 3. The Line of Dynamism

A single line separates the two computational models from [problem.md](problem.md).

```
        ────────────────────────────────────────────────────────────────
   L0-L5   DECLARATIVE ZONE    git -> evaluate -> check   (batch)
        ─────────────────────  Line of Dynamism  ───────────────────────
   L6      RUNTIME ZONE        reconcile -> instantiate -> reap   (continuous)
        ────────────────────────────────────────────────────────────────
```

Above the line, no state exists without an evaluation. Below it, state may be created, changed and
destroyed by events - but only as materialization of the desired state, and only through the
reconciler. The line is not a technology boundary (Nix below, Kubernetes above); it is a boundary
between *who owns the truth*, and it moves with each domain according to [ownership.md](ownership.md).

## 4. Invariants

Each invariant names the observation that would falsify it. A check that cannot fail loudly is not a
check ([`../../AGENTS.md`](../../AGENTS.md), non-negotiable 2).

| Id | Invariant | Falsified by |
|---|---|---|
| **R1** | **Stratification.** No layer is reconciled by a layer that depends on it; in particular the reconciler never manages its own substrate, network, firewall or authenticating identity. | A control-plane object whose absence prevents the control plane from starting. |
| **R2** | **Purity.** Nix evaluation reads run-time truth only through a pinned snapshot; no live import, no import-from-derivation against a mutable source. | An evaluation whose result changes without a commit. |
| **R3** | **Single writer.** Every resource class, and within it every field, has exactly one owner. | Two writers producing flapping reconciliation. |
| **R4** | **Owned is enforced, observed is never overwritten.** | A UI-created entity disappears after a reconcile. |
| **R5** | **Level-triggered convergence.** Reconcile is idempotent and order-independent; a lost event still converges. | An entity that only exists if its event arrived. |
| **R6** | **Derived is a pure function of declared and observed.** No hidden third source. | Two reconciles of the same inputs disagree. |
| **R7** | **Hybrid by pace.** Only fast, multi-actor domains are reconciled; slow, single-actor domains stay batch. | A static service moved into the reconciler without need. |
| **R8** | **Static independence.** Boot and static serving never depend on the reconciler. | A host that cannot serve DNS/ingress while the control plane is down. |
| **R9** | **Reproducibility scope.** Bit-reproducibility holds for artifacts and substrate, not for observed run-time state. | A claim that a UI-created user is a Nix artifact. |
| **R10** | **Explicit deletion.** Every class declares its deletion policy: cascade, orphan, quarantine or TTL. | Orphaned secrets, backups or DNS records after an entity is gone. |
| **R11** | **Drift is loud.** Divergence between derived and actual is a measurable, alerting signal. | Drift that is only visible in a log. |
| **R12** | **Bounded blast radius.** The control-plane API is mesh-only, authenticated, authorised and additive-only for owned policy where feasible, with a break-glass path. | An unauthenticated API server reachable from a public network. |

## 5. What the model deliberately does not claim

`Derived` is reproducible; `Observed` is not. A system that pretends otherwise will chase an impossible
invariant (**R9**). The correct ambition is a *defined* boundary, a *pure* translation across it, and a
*measurable* reconciliation - not a single source of truth, which does not exist in any system with a
UI, a human, or a clock.
