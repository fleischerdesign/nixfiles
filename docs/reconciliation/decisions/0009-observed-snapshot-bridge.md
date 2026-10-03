# 0009 - Observed-snapshot bridge

- **Status:** accepted
- **Date:** 2026-10-03

## Context

Some declared artifacts genuinely depend on observed truth - a name list, a member list, a rendered
configuration. Reading that truth live during evaluation would make Nix output unpredictable and destroy
reproducibility (**R2**). Reading nothing leaves the declared artifact stale.

## Decision

Run-time truth enters Nix only through a **pinned snapshot**: the reconciler exports a content-addressed,
dated artifact, and evaluation consumes that immutable reference. There is exactly one bridge, and it
runs from runtime to Nix - never the other way.

## Consequences

- Evaluation stays pure; a commit plus a pinned snapshot determines the output.
- Every consumer knows the snapshot's age, so staleness is explicit, not hidden.
- The bridge is an export step that must be tested for determinism and for containing no secret values.
- A domain that needs the bridge is more expensive than one that does not; prefer deriving in the
  reconciler unless the artifact must be a Nix build.

## Alternatives

- **Live import / IFD against a mutable source** - refused; it trades reproducibility for convenience.
- **No bridge (freeze the list)** - the present staleness, restated.
- **Two-way bridge** - would let Nix write run-time truth, reintroducing the two-writer problem.
