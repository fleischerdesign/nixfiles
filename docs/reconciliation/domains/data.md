# Domain: data

> State is the least forgiving domain: a mistake here is not a reconcile that flaps, it is data lost.
> This document reuses the repository's existing storage vocabulary
> ([`../../../contracts/storage/nixos.nix`](../../../contracts/storage/nixos.nix),
> [`../../../contracts/backup/nixos.nix`](../../../contracts/backup/nixos.nix)) and adds only the run-time
> counterpart. Touches **R9**, **R10**; references decisions **D5**, **D11**.

## 1. Two kinds of data

| Data | Owner | Lifecycle | Deletion default |
|---|---|---|---|
| Platform data (PostgreSQL, media, mail) | repository (Nix) | the host's | restic, unchanged |
| Control-plane state (datastore, objects) | control plane | the plane's | backed up, restored as a unit (**D5**) |
| Entity data (tenant DB, workspace, volume) | control plane | the entity's | **orphan**, never cascade (**R10**) |

## 2. Storage classes

The existing classes carry over unchanged, so a dynamic entity speaks the same language as a static
service:

| Class | Meaning | Backed up |
|---|---|---|
| data | irreplaceable | yes, mandatory |
| state | service state | yes |
| regenerable | rebuildable | no |
| cache | disposable | no |

A `kind` declares its classes; the reconciler realizes volumes/PVCs accordingly. A dynamic workload
with a `data` path and no backup class is a configuration error, exactly as a host without a backup
provider is today.

## 3. Where the bytes live

- **Local** (a host's disk) is the default: fast, and honest about being tied to a host.
- **Network** storage is introduced only when a workload must outlive its host, and only with the same
  care the fleet applies to any shared resource - it is a new failure domain, not a convenience.
- The choice is a per-host-class capability, measured in [baseline.md](../baseline.md), not assumed
  uniform across cloud and home.

## 4. Tenant databases

A tenant database is derived: a provider (SQL/CloudNativePG equivalent) creates the database, the role,
and a connection secret ([secrets.md](secrets.md)). The dangerous part is deletion, and the default is
**orphan**: removing the workload does not remove the database until an operator asserts it, because a
reconcile must never be able to destroy irreplaceable data (**R10**, **E12**).

## 5. Control-plane state

The plane's own state - the datastore and its persistent objects - is a declared backup class with a
drilled restore (**D5**). Losing it and restoring it is a first-class scenario (**S13**,
[bootstrap.md](../bootstrap.md) §6), not an edge case. A plane whose state is not backed up is a plane
that has already lost the dynamic fleet once.

## 6. Boundary

Platform data stays Nix. Only entity data and the plane's own state are reconciled. If the layer is
removed, entity data is exported/migrated per the class deletion policy; it is never silently dropped
on rollback ([migration.md](../migration.md) §5).

## 7. Checks

`reconciliation-orphans` (delete leaves no database or volume by accident), a restore drill for the
plane's state, and a class check that a `data` path always carries a backup class. See
[checks.md](../checks.md).
