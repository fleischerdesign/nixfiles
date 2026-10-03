# 0002 - Desired-state delivery: Flux

- **Status:** accepted
- **Date:** 2026-10-03

## Context

The control plane needs to receive its desired state from Git and keep it reconciled, so that declared
policy is versioned, reviewed and reproducible. Nix already compiles desired state; something must
deliver and continuously reconcile it inside the control plane.

## Decision

Use **Flux** as the delivery and GitOps controller, consuming manifests rendered by Nix
(see [0004](0004-nix-as-compiler.md)).

## Consequences

- Delivery is controller-based and composable; no separate UI or opinionated application model.
- Drift of declared objects is corrected, and the correction is observable (**R11**).
- Flux is one more component to operate and to pin; it is pinned by Nix like every other artifact.
- The boundary between "Nix renders" and "Flux reconciles" is explicit: Nix never talks to the cluster's
  run-time state, Flux never evaluates Nix.

## Alternatives

- **Argo CD** - capable and common, but brings a UI and an application-centric model the fleet does not
  need, and more surface than the problem requires.
- **Direct `kubectl apply` from a hook** - batch again; loses exactly the continuous property this
  layer exists to add.
- **No GitOps layer (engine watches Git directly)** - possible for Crossplane alone, but conflates
  delivery with reconciliation and gives up the standard, well-understood boundary.
