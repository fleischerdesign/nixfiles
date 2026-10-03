# Bootstrap

> The chicken-and-egg problem of any control plane: it cannot manage the things it depends on
> (**R1**). This document fixes the sequence, the seed, the adoption step, and the recovery from a
> bootstrap that was interrupted.

## 1. The stratification, made concrete

```
   NixOS seed  ──►  k3s  ──►  Flux  ──►  Crossplane + providers  ──►  workloads
   (L0-L3)         (API)     (delivery)  (engine)                     (L6)
   ▲                                                                    │
   └──────────────────── never reconciled by the plane ────────────────┘
```

Everything left of Flux is Nix and is never reconciled by the plane. Everything from Crossplane
rightwards is. The boundary is a single, named edge.

## 2. The seed

NixOS installs and starts:

- **k3s** with a server token from SOPS, mesh-only listener, Traefik/service-LB/local-storage disabled;
- the **Flux** entry point, pinned to a Git commit or a rendered artifact reference;
- the **CRDs** needed for the first domains.

The seed is a NixOS generation. `nixos-rebuild --rollback` removes the entire control plane in one
step, which is the property that keeps Phase 0 reversible.

## 3. Adoption

The control plane adopts objects that already exist; it does not recreate them. Adoption is the step
that prevents a bootstrap from destroying live state:

1. Flux applies the declared **platform** objects (new, empty).
2. A provider **imports** pre-existing external resources (an Authentik application, a DNS record) as
   observed objects, annotated with the ownership label.
3. Only then does a composition begin to own the fields it declares.

An import that would delete or recreate an existing resource is a defect, not a bootstrap.

## 4. Ordering and idempotency

- **Ordering:** L0-L3 must be healthy before the seed; the seed before delivery; delivery before
  domains. Because the plane is level-triggered (**R5**), all of this converges after the fact - the
  ordering is a convenience, not a correctness requirement.
- **Interruption:** a power loss at any step is safe. On restart the same desired state is reconciled
  again; adoption is idempotent; an object that was imported twice is a no-op.
- **Seed drift:** if a human edits the cluster by hand, Flux corrects it (**R11**). The seed is desired
  state, not a snapshot of history.

## 5. Break-glass

The control plane authenticates through Authentik, but Authentik is platform. Losing Authentik must not
lock the operator out of the plane:

- a local administrator credential, generated at seed time, stored outside Authentik, rotated on use;
- documented in [operations.md](operations.md), exercised in a drill, never used routinely.

## 6. Recovery

Two distinct events, two distinct procedures:

- **Lost a host:** rebuild from Nix; the plane is the seed again; workloads reschedule if capacity
  allows (see [operations.md](operations.md) §4).
- **Lost the control plane's state:** restore the datastore and persistent state from the class's backup
  (**D5**), then let reconciliation converge. If no state backup exists, the plane is re-seeded and
  observed entities are re-imported; derived entities are recreated; only run-time history is lost.

The second case is the reason the state backup is a first-class class rather than an afterthought.
