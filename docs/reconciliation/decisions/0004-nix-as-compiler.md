# 0004 - Nix is substrate and compiler, not system of record

- **Status:** accepted
- **Date:** 2026-10-03

## Context

Nix is a batch evaluator. It is the best available tool for a reproducible substrate and for pure
compilation of static desired state, and the wrong tool for entities that change between evaluations
(see [problem.md](../problem.md)). The repository's value - reproducibility, invariants, checks - rests
on Nix evaluation staying pure.

## Decision

Keep Nix as the **substrate** (NixOS) and the **compiler** of immutable artifacts and desired state
(rendered manifests, OCI images). Remove from it the role of **system of record for run-time entities**.
Run-time truth enters Nix only through a **pinned snapshot**, never through a live import.

## Consequences

- Nix evaluation remains pure and reproducible; **R2** is preserved.
- Desired state is still authored in one language and reviewed in one place; Flux consumes what Nix
  renders.
- Nix no longer enumerates entities it cannot know; the second truth lives in the control plane.
- Some facts now exist twice in representation - as a rendered manifest and as a live object - and their
  equivalence must be a check (**R6**, **R11**), not an assumption.

## Alternatives

- **Nix owns run time** (per-event `nixos-rebuild`) - the present blocker; rejected.
- **Impure Nix** (import-from-derivation against live APIs) - destroys the reproducibility that makes
  Nix worth keeping; refused.
- **Replace Nix with a Kubernetes-native config language** - discards a working, proven substrate and
  its checks for no gain.
