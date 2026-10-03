# Operations

> Day-2. Every procedure names its trigger, its steps, and what "done" looks like. The repository's
> operational rule applies unchanged: a step that cannot fail loudly is not a step. The existing
> [`../operations.md`](../operations.md) remains the fleet runbook; this document adds only what the
> reconciliation layer introduces.

## 1. Routine

| Procedure | Trigger | Done when |
|---|---|---|
| Apply a declared change | a commit | Flux has reconciled; drift signal is quiet |
| Upgrade the engine/providers | a pinned input bump | the reconciler reports healthy; no object left in a failed state |
| Rotate an entity secret | policy, or a leak | the new value is consumed; the old is gone from the store |
| Use break-glass | Authentik or the plane is unavailable | the action is audited; the credential is rotated |

## 2. Upgrades

Three independent version axes; upgrading one must not assume the others:

1. **Substrate** (NixOS generation) - a `nod switch`, with rollback available.
2. **Engine/providers** (pinned images) - a commit; pinned by digest.
3. **Schemas** (CRD versions) - the axis that can hurt, because stored objects outlive the process.

A schema change is additive first: add the new field, migrate, then remove the old. A change that makes
an existing stored object unreadable is a defect in the migration, not in the schema.

## 3. Rollback

"Rollback" means a forward reconcile to a previous desired state (**D6**), never time travel:

- revert the commit; Flux reconciles back;
- if the substrate rolled back (**`nixos-rebuild --rollback`**) but the objects did not, that skew is
  itself an incident: bring the schema down to what the substrate understands, then reconcile.

A dynamic action (a revoked access, a deleted entity) is not rolled back by un-revoking; it is reversed
by a new desired state that the reconciler applies.

## 4. Incidents

| Incident | Immediate | Recovery |
|---|---|---|
| Control plane down | static services continue (**R8**); do not bypass it | restart; reconcile; investigate why it stopped |
| Control-plane state lost | stop writers | restore from the state backup; re-import observed; recreate derived |
| A host is lost | its dynamic workloads are unavailable unless rescheduled | rebuild from Nix; the plane reseeds it |
| Drift will not stay corrected | freeze the offending writer | find the second writer (**R3**); this is the mishmash signal |
| Runaway provisioning | revoke the provider credential | delete out of band; add a quota; find the missing admission |
| Orphan after delete | record it | apply the class deletion policy (**R10**); close the gap in the composition |

The **drift-will-not-stay-corrected** case is the most important: it means the ownership model has a
hole, and the response is to restore the model, not to silence the signal.

## 5. Backup and restore

- **Platform state** (SOPS, host data): unchanged, restic.
- **Control-plane state** (datastore, persistent objects): its own declared class (**D5**), with a
  documented restore that is drilled, not assumed.
- **Entity state** (tenant data, workspace): the domain's backup class
  ([ownership.md](ownership.md) §5).

A restore is complete only when the reconciler converges afterward and the drift signal is quiet.

## 6. On-call and observability

The layer is observable or it is not operated: engine health, provider health, reconcile latency,
error rate, queue depth, and the drift signal all alert. The platform's existing monitoring remains the
home; dynamic targets join it through service discovery (**D4**), never through a second monitoring
stack.

## 7. Decommissioning

The plan's own expiry is an operation. When the layer is removed:

1. revert every domain across the line to Nix (**D14**);
2. drain dynamic entities through the class deletion policy - no hidden orphans;
3. remove the seed; the hosts return to Nix-only;
4. delete this package, having graduated its content into the specification.
