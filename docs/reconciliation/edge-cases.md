# Edge cases, scenarios and risks

> The audit. A model is not "thought through" because it is elegant; it is thought through because its
> failure modes, its boundary cases and its life beyond the two examples that motivated it are named.
> **D1..Dn** are open decisions, **S1..Sn** scenarios, **E1..En** risks. Invariants are in
> [model.md](model.md); gaps in the matrix are in [ownership.md](ownership.md).

## 1. Open decisions

| Id | Decision | Why it matters | Candidate resolution |
|---|---|---|---|
| **D1** | Where the control plane runs, and whether it is HA | A single node is simple but is a single point of failure for all dynamic work; a 3-node embedded-etcd quorum spanning two VPS and a residential link is fragile | Single server first (measure), HA only as a deliberate later decision |
| **D2** | Who writes internal (split-horizon) DNS for a dynamic name | Blocky/DNS is Nix-generated and must resolve dynamic names; the external record and the internal view can diverge | A DNS provider reconciling both views from observed names; split horizon stays a naming rule |
| **D3** | TLS/ACME gating for dynamic names | On-demand issuance for arbitrary names is a resource-exhaustion vector; per-name DNS-01 hits rate limits | Keep issuance inside one pre-issued wildcard; gate on-demand behind an allow-list (`ask`) |
| **D4** | Dynamic telemetry targets for a NixOS Prometheus | An unobservable workload is a defect; the platform Prometheus cannot read the control plane through Nix | Control-plane service discovery feeding Prometheus; telemetry is a required field, not optional |
| **D5** | Control-plane state backup and disaster recovery | The control plane holds entity definitions and secrets; losing it loses the dynamic fleet | Back up the datastore and persistent state as a declared class; seed plus state restores it |
| **D6** | Substrate/control-plane version skew and rollback | `nixos-rebuild --rollback` reverts the substrate but not the objects; a rollback can leave schema skew | Version the CRDs; define "rollback" as a forward reconcile to the previous desired state, never time travel |
| **D7** | Identity circularity: the control plane authenticates through Authentik | If Authentik runs *in* the control plane, the plane cannot start | Authentik is platform (beside/below the plane); break-glass admin independent of Authentik |
| **D8** | Appropriateness threshold for a five-host fleet | The control plane is new critical infrastructure; its operating cost can exceed its benefit | Adopt only above a measured churn/actor threshold; otherwise stay Nix (**R7**) |
| **D9** | Provider maturity and fallback | A community provider is a stability and supply-chain dependency | Prefer first-party (Terraform provider via `provider-terraform`); vendor the community provider otherwise |
| **D10** | Ownership and rotation of the secret bridge | The bridge is the only seam between two secret stores; a silent second path is a defect | One operator owns the bridge; rotation is a declared policy, audited |
| **D11** | Multi-tenant isolation and blast radius | Once users run workloads, namespaces and RBAC become security boundaries | Mesh-only API, OIDC + RBAC, quotas, network policy, admission |
| **D12** | Conflict resolution per field across owners | A UI edit to a declared field is either reverted or honoured - never undefined | Declared: enforce; observed: never overwrite; the choice is per field (**R4**) |
| **D13** | Prune/deletion safety | Automated pruning can destroy data or access | Ownership labels, finalizers, quarantine, dry-run gates before destructive applies |
| **D14** | The exit path back to Nix-only | Non-negotiable 1: prove the replacement before deleting the original | Run beside Nix; snapshot observed state back into a pinned Nix input; delete with no collateral |

## 2. Scenario catalogue

The two motivating cases (Authentik users, OpenClaw gateways) are the least interesting, because they
are the easiest. These are the ones that must not surprise the design:

| Id | Scenario | Where it lands |
|---|---|---|
| **S1** | A slow, single-actor service (PostgreSQL, Caddy, mesh) | Stays Nix (**R7**); the boundary of the model |
| **S2** | A per-owner long-lived instance, generalising OpenClaw to any service | Derived from observed membership; a `kind`, not a special case |
| **S3** | An ephemeral sandbox for a task or a session | Job + TTL + isolation class; the reason the runtime layer exists |
| **S4** | Tenant data provisioned with the tenant (database, bucket) | Provider-derived; deletion policy from [ownership.md](ownership.md) §3 |
| **S5** | A new public service published from a developer machine | Tunnel + external/internal DNS + TLS + identity, all derived |
| **S6** | An internal-only dynamic name | Split-horizon naming; **D2** applies |
| **S7** | A new device joins the mesh (WireGuard peer) | **Below** the line - inventory or an agent, never the reconciler (**R1**) |
| **S8** | A new IoT device joins the LAN | Below the line - `my.topology.devices`; never the reconciler |
| **S9** | A roaming client that is offline then returns | Consumer, not member; the mesh and firewall model is Nix |
| **S10** | Observability of a workload that lives for minutes | Service discovery (**D4**); Telemetry is a required class |
| **S11** | Backup and retention of tenant/ephemeral data | Derived backup object with the class's retention |
| **S12** | Secrets for an entity created at run time | Entity secret store, bridged (**D10**) |
| **S13** | Cold start or total loss of a host | Static independence (**R8**); rebuild from Nix plus state (**D5**) |
| **S14** | Reversing a dynamic action (revoke access) | Forward reconcile to the new desired state; not a time travel (**D6**) |
| **S15** | Upgrading the control plane while workloads run | Versioned CRDs, drain/surge; the substrate stays Nix |
| **S16** | Operating with the control plane down or unreachable | Degraded mode; dynamic work pauses, static work continues (**R8**) |

## 3. Risk register

| Id | Risk | Impact | Mitigation | Guarded by |
|---|---|---|---|---|
| **E1** | The API becomes the fleet's highest-value target | Full compromise | Mesh-only, OIDC + RBAC, quotas, pinned images | R12 |
| **E2** | Circular dependency with the authenticating identity | The plane cannot start | Identity is platform; break-glass | R1 |
| **E3** | Loss of control-plane state | Dynamic fleet lost | Declared state backup; seed rebuild | D5 |
| **E4** | WAN quorum fragility | HA fails worse than single node | Measure; prefer a single node until justified | D1 |
| **E5** | Runaway provisioning | Resource and cost exhaustion | Quotas, rate limits, admission | R12 |
| **E6** | Orphaned resources, data and secrets | Silent cost, stale access, data loss | Class deletion policy; drift signal | R10, R11 |
| **E7** | Controller/provider supply-chain drift | Compromise or breakage | Nix-pinned digests, vendored providers | R12 |
| **E8** | Substrate rollback with state skew | Inconsistent fleet | Versioned schema; forward reconcile | D6 |
| **E9** | Two writers on one class | Flapping, the core mishmash | Single-writer per field, admission | R3, R4 |
| **E10** | Over-engineering for a small fleet | Operational cost > benefit | Hybrid by pace; measured threshold | R7, D8 |
| **E11** | Unbounded metric cardinality from ephemeral targets | Observability outage | Labels bounded; targets dropped on reaping | D4 |
| **E12** | Destructive prune | Data/access loss | Finalizers, quarantine, dry-run gates | D13 |
| **E13** | Secret sprawl across two stores | Leakage, rotation gaps | One bridge, audited, declared rotation | D10 |
| **E14** | Purity eroded by a run-time shortcut | Reproducibility lost | Live imports and IFD refused at review | R2 |

## 4. What a complete design must answer

A domain may cross the line only when **D1..D14** that concern it are decided and each **S** that touches
it has a stated landing place. Anything less is the state this package exists to replace: a model that
works for the example and fails for the fleet.
