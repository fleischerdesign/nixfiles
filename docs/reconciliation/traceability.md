# Traceability

> The completeness index. Every invariant, open decision, scenario and risk is listed once with the
> document that owns it. A row whose owner is *unassigned* is a gap; a row whose status is *open* is a
> decision still to be made. This is the check that the plan covers everything it claims to.

## 1. Invariants (**R**) -> owner and check

| Invariant | Owned by | Checked by |
|---|---|---|
| R1 stratification | [model.md](model.md), [architecture.md](architecture.md) §2, [domains/network.md](domains/network.md) | `reconciliation-stratification` |
| R2 purity | [reproducibility.md](reproducibility.md) | `reconciliation-purity` |
| R3 single writer | [ownership.md](ownership.md) §1, [decisions/0007](decisions/0007-ownership-labels-and-admission.md) | `reconciliation-ownership` |
| R4 observed preserved | [domains/identity.md](domains/identity.md) §3 | `reconciliation-preservation` |
| R5 convergence | [model.md](model.md) §4, [domains/workloads.md](domains/workloads.md) §4 | `reconciliation-convergence` |
| R6 derived is a function | [model.md](model.md) §2, [reproducibility.md](reproducibility.md) §4 | `reconciliation-determinism` |
| R7 hybrid by pace | [decisions/0006](decisions/0006-scope-hybrid-by-pace.md), [baseline.md](baseline.md) §4 | `reconciliation-scope` |
| R8 static independence | [architecture.md](architecture.md) §7 | `reconciliation-degraded` |
| R9 reproducibility scope | [reproducibility.md](reproducibility.md) | `reconciliation-repro` |
| R10 explicit deletion | [ownership.md](ownership.md) §3, [domains/data.md](domains/data.md) §4 | `reconciliation-orphans` |
| R11 loud drift | [domains/observability.md](domains/observability.md) §4 | `reconciliation-drift` |
| R12 bounded blast radius | [security.md](security.md), [domains/network.md](domains/network.md) §2 | `reconciliation-exposure` |

## 2. Open decisions (**D**) -> owner

| Id | Decision | Owner | Status |
|---|---|---|---|
| D1 | control-plane placement and HA | [baseline.md](baseline.md) B1-B3/B10, [domains/network.md](domains/network.md) | open |
| D2 | internal DNS for dynamic names | [domains/exposure.md](domains/exposure.md) §4, [decisions/0011](decisions/0011-internal-dns-reconciliation.md) | decided in principle, implementation open |
| D3 | TLS/ACME gating | [domains/exposure.md](domains/exposure.md) §5 | open |
| D4 | dynamic telemetry targets | [domains/observability.md](domains/observability.md) §1 | open |
| D5 | control-plane state backup | [domains/data.md](domains/data.md) §5, [operations.md](operations.md) §5 | open |
| D6 | version skew and rollback | [operations.md](operations.md) §3 | open |
| D7 | identity auth circularity | [bootstrap.md](bootstrap.md) §5, [security.md](security.md) §4 | open |
| D8 | appropriateness threshold | [baseline.md](baseline.md) §4, [decisions/0006](decisions/0006-scope-hybrid-by-pace.md) | decided as a rule, value open |
| D9 | provider maturity and fallback | [domains/identity.md](domains/identity.md) §5 | open |
| D10 | secret bridge ownership and rotation | [domains/secrets.md](domains/secrets.md), [decisions/0010](decisions/0010-secrets-two-store-bridge.md) | decided in principle, implementation open |
| D11 | multi-tenant isolation and blast radius | [domains/network.md](domains/network.md) §4, [security.md](security.md) §3 | open |
| D12 | per-field conflict resolution | [domains/identity.md](domains/identity.md) §3, [decisions/0007](decisions/0007-ownership-labels-and-admission.md) | decided as a rule |
| D13 | prune and deletion safety | [domains/data.md](domains/data.md) §4, [domains/workloads.md](domains/workloads.md) §4 | open |
| D14 | exit path back to Nix-only | [migration.md](migration.md) §1, [operations.md](operations.md) §7 | open |

## 3. Scenarios (**S**) -> landing place

| Id | Scenario | Landing place |
|---|---|---|
| S1 | slow, single-actor service | stays Nix ([decisions/0006](decisions/0006-scope-hybrid-by-pace.md)) |
| S2 | per-owner long-lived instance | [domains/workloads.md](domains/workloads.md) |
| S3 | ephemeral sandbox | [domains/workloads.md](domains/workloads.md) §1 |
| S4 | tenant data provisioned | [domains/data.md](domains/data.md) §4 |
| S5 | new public service from a dev machine | [domains/exposure.md](domains/exposure.md) |
| S6 | internal-only dynamic name | [domains/exposure.md](domains/exposure.md) §4 |
| S7 | device joins the mesh | below the line: [domains/network.md](domains/network.md), [migration.md](migration.md) §7 |
| S8 | IoT device joins the LAN | below the line: [migration.md](migration.md) §7 |
| S9 | roaming client returns | consumer: [migration.md](migration.md) §7 |
| S10 | observability of a minutes-long workload | [domains/observability.md](domains/observability.md) §3 |
| S11 | backup and retention of tenant data | [domains/data.md](domains/data.md) §2 |
| S12 | secrets for a run-time entity | [domains/secrets.md](domains/secrets.md) |
| S13 | cold start or total host loss | [bootstrap.md](bootstrap.md) §6 |
| S14 | reversing a dynamic action | [operations.md](operations.md) §3 |
| S15 | upgrading the plane while workloads run | [operations.md](operations.md) §2 |
| S16 | operating with the plane down | [architecture.md](architecture.md) §7, [operations.md](operations.md) §4 |

## 4. Risks (**E**) -> mitigation

| Id | Risk | Mitigation owned by |
|---|---|---|
| E1 | API is the highest-value target | [security.md](security.md) §2-4 |
| E2 | circular dependency with identity | [bootstrap.md](bootstrap.md) §5 |
| E3 | control-plane state lost | [domains/data.md](domains/data.md) §5 |
| E4 | WAN quorum fragility | [baseline.md](baseline.md) B10, [decisions/0001](decisions/0001-substrate-k3s.md) |
| E5 | runaway provisioning | [domains/workloads.md](domains/workloads.md) §5 |
| E6 | orphaned resources | [ownership.md](ownership.md) §3 |
| E7 | supply-chain drift | [security.md](security.md) §5 |
| E8 | substrate rollback with state skew | [operations.md](operations.md) §3 |
| E9 | two writers | [decisions/0007](decisions/0007-ownership-labels-and-admission.md) |
| E10 | over-engineering a small fleet | [decisions/0006](decisions/0006-scope-hybrid-by-pace.md) |
| E11 | unbounded metric cardinality | [domains/observability.md](domains/observability.md) §3 |
| E12 | destructive prune | [domains/data.md](domains/data.md) §4 |
| E13 | secret sprawl | [domains/secrets.md](domains/secrets.md) |
| E14 | purity eroded by a shortcut | [reproducibility.md](reproducibility.md) §2 |
