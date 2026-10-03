# Testing

> A check must be able to fail loudly, and the expectation is written next to the measurement
> ([`../../AGENTS.md`](../../AGENTS.md)). This document defines the test pyramid for the reconciliation
> layer, in the style the repository already uses: fixtures, assertions, and a measurement at the
> consumer - never only at the builder.

## 1. The pyramid

| Level | What it proves | Where it runs |
|---|---|---|
| Schema conformance | a `kind`'s CRD matches its composition | build time |
| Composition unit | a desired object yields exactly the intended resources | build time, no cluster |
| Provider contract | an external API maps to objects idempotently | against a disposable instance |
| Reconciliation conformance | the same fixture converges on the real engine | a disposable control plane |
| Drift and preservation | drift is corrected; observed entities survive | disposable control plane |
| Lifecycle end-to-end | create, health, inactivity, delete, no orphans | disposable control plane |
| Degraded mode | static services serve while the plane is stopped | one host class at a time |

## 2. What each level asserts

- **Schema conformance.** The XRD and the composition agree; a field the composition reads exists; a
  field it writes is owned. Falsifier: a rendered object a composition cannot produce.
- **Composition unit.** Feed one object, expect an exact resource set - no more, no less. This is where
  "one object becomes five" is pinned.
- **Provider contract.** Import an external resource, change nothing, reconcile, expect no change
  (idempotence). Change the external resource, reconcile, expect the observed field to update without
  a write back (**R4**).
- **Reconciliation conformance.** The same fixture converges on the real engine, not a mock. This is
  the analogue of [`../../checks/directory-runtime.nix`](../../checks/directory-runtime.nix), which runs
  the real bytes in a disposable PostgreSQL rather than asserting on configuration.
- **Drift and preservation.** Perturb a declared field, expect correction and a signal (**R11**).
  Create an observed entity that no declaration mentions, expect it to survive (**R4**). Both, not
  either: a suite that only proves correction cannot prove it leaves the observed alone.
- **Lifecycle end-to-end.** For one `kind`: create, health, inactivity, delete; then assert the absence
  of every orphan - name, secret, snapshot, database (**R10**, **E6**).
- **Degraded mode.** With the plane stopped, a host boots and serves its static services
  (**R8**); boot time is compared against baseline B14.

## 3. Rules

1. **Disposable runtime, real bytes.** Run the shipped unit scripts and the real engine, as
   `checks/directory-runtime.nix` does, not a hand-written mock.
2. **Negative controls.** Every check has a companion that breaks the fact and expects the failure
   message, so a passing check is distinguishable from a check that never ran.
3. **The measurement at the consumer.** Whether a name resolves, whether a socket is reachable, whether
   a user survives - read at the level the consumer sees it.
4. **No secret leaves the store.** A rendered manifest or a test log that contains a secret value fails
   the build.
5. **Time is a parameter.** Inactivity, TTL and resync are driven by an injectable clock, so the tests
   are deterministic and the real intervals are configurable.

## 4. Continuous integration

`nix flake check` gains the build-time levels (schema, unit, rendered-manifest determinism). The
cluster levels require an ephemeral control plane, brought up by the same Nix expression that seeds the
real one, and torn down unconditionally. A level that cannot run in CI is a phase exit criterion that
must be run by hand, with the expectation recorded - not silently dropped.
