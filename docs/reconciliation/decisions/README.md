# Decisions

> Architecture Decision Records for the reconciliation layer. One decision per file, each stating the
> context, the decision, its consequences and the alternatives that were rejected. Decisions are
> immutable once accepted: a reversal is a new ADR that supersedes the old one, never an edit.

| Id | Decision | Status |
|---|---|---|
| [0001](0001-substrate-k3s.md) | Control-plane substrate: k3s | accepted |
| [0002](0002-delivery-flux.md) | Desired-state delivery: Flux | accepted |
| [0003](0003-engine-crossplane.md) | Reconciliation engine: Crossplane | accepted |
| [0004](0004-nix-as-compiler.md) | Nix is substrate and compiler, not system of record | accepted |
| [0005](0005-identity-ownership.md) | Identity: policy is declared, entities are observed | accepted |
| [0006](0006-scope-hybrid-by-pace.md) | Scope: hybrid by pace | accepted |

## Format

Each record answers four questions:

- **Context** - the forces that make a decision necessary.
- **Decision** - what was chosen, in the active voice.
- **Consequences** - what becomes easier, what becomes harder, and what is now bound.
- **Alternatives** - what was rejected, and why.

A record that cannot name its falsifier is not a decision; it is a preference.
