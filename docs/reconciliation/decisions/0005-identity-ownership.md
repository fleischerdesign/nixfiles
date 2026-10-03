# 0005 - Identity: policy is declared, entities are observed

- **Status:** accepted
- **Date:** 2026-10-03

## Context

Users are created in the Authentik UI and group membership changes at run time. The repository can and
should declare the policy - which groups exist, which audiences they grant, which application objects
the policy projects - but it cannot honestly declare a person who exists only after an operator clicks
in the UI. Attempts to enumerate entities in Nix produce the rebuild-per-membership blocker and a
permanently stale list.

## Decision

Split identity along the ownership line: **policy is declared** (Git-owned, enforced) and **entities
are observed** (directory-owned, imported, never overwritten). Derived artifacts - per-member groups,
applications, access bindings - are computed from the two by the reconciler.

## Consequences

- A UI-created user is never deleted by a reconcile (**R4**); this is the acceptance test of Phase 2.
- The repository declares intent, not population; the directory remains the population's source.
- Per-member artifacts (currently compiled at evaluation time, e.g. OpenClaw gateways) become derived
  objects, which is what makes them react without a rebuild.
- A deliberate conflict (a declared field edited in the UI) has a defined winner per field (**D12**).

## Alternatives

- **Declare users in Nix** - fights the UI, requires per-user edits, and breaks on the first UI-created
  account; the present pain.
- **Let the directory own policy too** - policy drifts out of Git and out of review; rejects the
  repository's model.
- **Freeze entity creation to a pipeline** - removes the UI's legitimate use and adds a process where
  the ownership split already solves it.
