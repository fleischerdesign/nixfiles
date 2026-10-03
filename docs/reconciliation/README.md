# Runtime reconciliation

> **Status:** design package, **not** a specification of the present.
> **Expiry:** when accepted, its content graduates into [`../architecture.md`](../architecture.md),
> [`../naming.md`](../naming.md), [`../identity.md`](../identity.md) and [`../security.md`](../security.md),
> and this directory is deleted. A plan that outlives its implementation describes two states at once;
> [`../README.md`](../README.md) forbids exactly that.

## Thesis

The fleet is built on **batch reconciliation**: a human or a hook evaluates Nix, and the result is
applied once. That model cannot express state that must change between two evaluations - a user created
in the Authentik UI, a group membership, a workload that exists only while a session runs. Those are not
an anomaly to be eliminated; they are a second, correct source of state. This package defines where the
first truth (declared, compiled by Nix) ends, where the second (observed, owned by the runtime) begins,
and the reconciler that continuously converges the derived state between them.

- **Not a rewrite.** NixOS remains the substrate; Nix remains the compiler of immutable artifacts and
  pure policy. It stops being the system of record for run-time entities.
- **Not a per-use-case reconciler.** One generic engine, extended by providers and compositions;
  domain logic is data, not code.
- **Not a monolith.** The reconciler governs only what changes fast and by multiple actors. Everything
  slow stays Nix. See [`decisions/0006-scope-hybrid-by-pace.md`](decisions/0006-scope-hybrid-by-pace.md).

## The map

| Question | Document |
|---|---|
| Why does the current paradigm block us, and what is the actual paradigm shift? | [problem.md](problem.md) |
| What are the layers, the planes, the state classes and the invariants? | [model.md](model.md) |
| What is the target stack, Nix's role, bootstrap and security model? | [architecture.md](architecture.md) |
| Who owns which field of which domain, and what happens on deletion? | [ownership.md](ownership.md) |
| Which edge cases, scenarios and risks are unclosed? | [edge-cases.md](edge-cases.md) |
| How do we adopt this without a big bang, and when do we stop? | [roadmap.md](roadmap.md) |
| What do the terms mean? | [glossary.md](glossary.md) |
| Which decisions were made, and which alternatives were rejected? | [decisions/](decisions/README.md) |

## Principles

1. **One source per property.** The failures this package exists to prevent all reduce to one property
   being written by two writers. Ownership is per field, not per object (see [ownership.md](ownership.md)).
2. **Nix evaluation stays pure.** Run-time truth enters Nix only through pinned snapshots, never through
   live imports or import-from-derivation. Purity is the property that makes this repository valuable;
   an impure shortcut trades it for convenience and is refused.
3. **The reconciler never reaches below itself.** Network, firewall and the identity the control plane
   authenticates with are strictly beneath it - see invariant **R1** in [model.md](model.md).
4. **Convergence is level-triggered; reaction is edge-triggered.** Events make it fast; the periodic
   resync makes it correct. A lost event must never mean a lost entity.
5. **Failure is bounded.** A control-plane outage degrades dynamic features only. Static serving and
   boot never depend on it.
6. **The plan has an exit.** Every phase can be reverted to the present Nix-only fleet without
   collateral damage - the repository's first non-negotiable, applied to architecture.

## How to read

- Read [problem.md](problem.md) and [model.md](model.md) before anything downstream; they define the
  vocabulary the other files use without redefining it.
- Invariants are named **R1..Rn** (reconciliation) to avoid colliding with the naming invariants
  **I1..I10** in [`../naming.md`](../naming.md). Each is stated once, in [model.md](model.md).
- Open questions are named **D1..Dn** and tracked once, in [edge-cases.md](edge-cases.md).
- English throughout, ASCII diagrams, lowercase file names - the conventions of [`../README.md`](../README.md).
