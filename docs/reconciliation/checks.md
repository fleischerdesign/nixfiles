# Checks

> Invariants are only as real as the check that can fail. This maps every invariant in
> [model.md](model.md) to a check in the style of [`../../checks/`](../../checks/): an evaluation
> fixture, an assertion, and a measurement at the consumer. A row with no check is an open gap.

## 1. The mapping

| Invariant | Check | Kind | Measurement (the consumer's view) |
|---|---|---|---|
| **R1** stratification | `reconciliation-stratification` | eval fixture | no control-plane object is a dependency of the plane's own start; the seed graph is acyclic |
| **R2** purity | `reconciliation-purity` | build | evaluate twice; rendered manifests are byte-identical; no impure builtin in the render path |
| **R3** single writer | `reconciliation-ownership` | admission + eval | every object carries exactly one ownership label; a second writer is rejected |
| **R4** observed preserved | `reconciliation-preservation` | disposable cluster | an entity created out of band survives N reconciling passes |
| **R5** convergence | `reconciliation-convergence` | disposable cluster | delete a random event; the entity still appears after resync |
| **R6** derived is a function | `reconciliation-determinism` | disposable cluster | same inputs reconciled twice yield the same result |
| **R7** hybrid by pace | `reconciliation-scope` | eval fixture | a slow domain is not a reconciled object; the threshold from baseline.md is cited |
| **R8** static independence | `reconciliation-degraded` | per host class | with the plane stopped, boot and static serving succeed; boot time vs baseline B14 |
| **R9** reproducibility scope | `reconciliation-repro` | build | substrate and artifacts rebuild from a commit; observed state is never claimed as such |
| **R10** explicit deletion | `reconciliation-orphans` | disposable cluster | after delete: no name, secret, snapshot or database remains |
| **R11** loud drift | `reconciliation-drift` | disposable cluster | a perturbed declared field is corrected and emits a signal |
| **R12** bounded blast radius | `reconciliation-exposure` | eval fixture + live | the API is mesh-only; it appears as one declared endpoint; `exposure-audit --strict` is quiet |

## 2. Check conventions

These follow the repository's existing three patterns (see
[`../../checks/`](../../checks/) for the originals):

- **Eval fixture** - `lib.evalModules` with a synthetic input, plus negative controls that break the
  fact and expect a specific message (`checks/topology-inventory.nix`).
- **Build measurement** - build the real artifact and assert on its bytes (`checks/caddy-auth-order.nix`
  runs `caddy adapt`).
- **Disposable runtime** - run the shipped bytes in a throwaway instance and measure the effect
  (`checks/directory-runtime.nix` runs the real importer against a disposable PostgreSQL). This is the
  pattern the reconciliation checks generalize; it is why the layer can be tested without a fleet.

## 3. Negative controls

Every check above has a companion that breaks its fact and expects the failure. A check without a
negative control cannot be distinguished from one that never ran, which is the failure the repository's
second non-negotiable names explicitly.

## 4. Wiring

Build-time checks join `nix flake check` (`checks.${system}` in [`../../flake.nix`](../../flake.nix)).
Cluster-level checks run against an ephemeral control plane brought up by the same Nix expression that
seeds the real one, and torn down unconditionally. A cluster-level check that cannot run in CI is run by
hand at the phase exit, and its expectation is recorded in [baseline.md](baseline.md), not dropped.
