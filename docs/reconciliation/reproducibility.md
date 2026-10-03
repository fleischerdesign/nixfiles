# Reproducibility

> Invariant **R2** (purity) and **R9** (scope of reproducibility) are the two facts that keep this
> layer from eroding what makes the repository valuable. This document states precisely what remains
> reproducible, what does not, and the only permitted seam between them.

## 1. The two halves

| Property | Holds for | Does not hold for |
|---|---|---|
| Bit-reproducibility | substrate, artifacts, rendered manifests | observed run-time entities |
| Determinism of evaluation | Nix evaluation over declared inputs | the contents of a UI or a database |
| Rebuild from history | a NixOS generation | the control plane's event history |

A UI-created user is not a Nix artifact and never will be; claiming otherwise is the error **R9**
forbids. The correct ambition is a *pure translation* across a *defined boundary*, not a single source
of truth.

## 2. Purity of evaluation (R2)

Nix evaluation may read run-time truth only through a **pinned snapshot**: an immutable artifact
identified by content (a store path, an OCI digest, a commit). It may not:

- read a live API during evaluation;
- use import-from-derivation against a mutable source;
- depend on wall-clock time, a host name, or the network.

A forbidden shortcut is refused at review even when it is convenient: it converts a reproducible system
into one whose output cannot be predicted from a commit. The check is simple and falsifiable - evaluate
twice, expect byte-identical output.

## 3. The snapshot bridge

When a declared artifact genuinely depends on observed truth, the dependency is made explicit and
pinned (**D14**, [decisions/0009-observed-snapshot-bridge.md](decisions/0009-observed-snapshot-bridge.md)):

```
observed (runtime)  ──export──►  snapshot (immutable, pinned)  ──evaluate──►  declared artifact
```

The snapshot is content-addressed and dated. It carries the timestamp of its observation, so a
consumer always knows how stale it is. The bridge is one-directional from runtime to Nix; there is no
path from Nix into live state except through the reconciler.

## 4. Rendered manifests

Nix renders desired state (manifests) that Flux applies. Rendering is deterministic: the same commit
yields the same manifests. Flux consumes them by pinned reference (a Git commit or an OCI artifact),
never by re-evaluating Nix. This keeps the two halves on the same contract: what Nix rendered and what
the control plane holds must be provably equal when nothing has legitimately diverged (**R6**), and
their difference is measured (**R11**).

## 5. What this buys

- A host rebuilds identically from a commit.
- An artifact rebuilds identically from a commit.
- The run-time half is *understood* rather than *denied*: it is observed, it is backed up, and it has an
  owner - but it is not claimed to be reproducible.
