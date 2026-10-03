# 0010 - Secrets: two stores, one bridge

- **Status:** accepted
- **Date:** 2026-10-03

## Context

Platform secrets live in SOPS in Git. Entity secrets do not exist until run time and must never enter
Git. Two stores are unavoidable; two *uncontrolled* stores are a defect (**E13**, **D10**).

## Decision

Keep SOPS for platform secrets and the control-plane store for entity secrets. Connect them with
**exactly one** operator - the bridge - which can surface a platform value into the plane and an entity
value to a host unit. No other path between the stores exists.

## Consequences

- The boundary is auditable: one component, one set of permissions, one rotation story.
- Rendered manifests and logs carry secret references, never values; a build check enforces it.
- An orphaned entity secret is treated like any other orphan and revoked by the class deletion policy.
- The entity store is inside the highest-value asset and inherits its threat model
  ([security.md](../security.md) §4).

## Alternatives

- **Everything in SOPS** - entity secrets cannot be committed; rejected.
- **Everything in the plane** - moves platform secrets out of review and reproducibility; rejected.
- **Multiple bridges (one per consumer)** - reintroduces silent paths and rotation gaps; rejected.
