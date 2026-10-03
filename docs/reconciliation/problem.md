# The problem

> This document states *why* the fleet needs a reconciliation layer. The vocabulary it uses -
> declared, observed, derived, batch, continuous - is defined in [glossary.md](glossary.md) and used
> normatively in [model.md](model.md).

## 1. Two computational models, not two philosophies

The industry opposition between "declarative" and "imperative" is a false one. Terraform, Nix,
CloudFormation and Kubernetes are all declarative: each takes a desired state and moves reality toward
it. The meaningful distinction is **how often the loop runs**:

| | Batch reconciliation | Continuous reconciliation |
|---|---|---|
| Examples | Nix, Terraform, CloudFormation | Kubernetes, Crossplane, operators |
| Trigger | a human or a hook | an event, plus a periodic resync |
| Lifetime of the loop | one invocation | the life of the process |
| Drift between runs | unseen until the next run | detected and corrected on its own |
| Reaction latency | minutes (evaluate, build, activate) | seconds |

Nix is a **compiler with batch activation**, and a very good one. It is not - and cannot be made into -
a long-running control loop. That is not a shortcoming to patch; it is a different computational model.
Every attempt to force run-time behavior through Nix - import-from-derivation against a live API,
impure evaluation, a rebuild per event - is an attempt to run a control loop at compile time. It is why
the current fleet is blocked.

## 2. The second truth is real and correct

State that originates outside the repository is not noise:

- A **user created in the Authentik UI**. The repository can declare the groups and the policy; it
  cannot declare a person who does not exist until an operator clicks in the UI.
- A **group membership**. The directory contract projects membership into artifacts, but the membership
  itself is directory-owned ([`../identity.md`](../identity.md)).
- An **OpenClaw personal gateway** that exists because its owner is in `ai-users`
  ([`../../features/services/openclaw/gateways.nix`](../../features/services/openclaw/gateways.nix)).
- A transient **sandbox** that lives for the duration of a session and then must be reaped.
- A **DNS record** for a name that only exists at run time.

Under the batch model, every one of these is a `nix flake check` and a `nod switch` away - a global,
blocking rebuild, though the fact it materializes is already known to the runtime.

## 3. The failure of both shortcuts

- **Shortcut A - make Nix own the run time.** The gateway's existence becomes a function of Nix
  evaluation. Correct but inert: the persona, the audience and the port are build inputs, so a new
  member forces evaluation, build and activation. This is the present state.
- **Shortcut B - let the run time run free.** Something mutates Authentik, k3s or Caddy at run time and
  Nix pretends not to see it. Now two writers touch the same object, drift is silent, and no document
  is true. This is the mishmash the repository's own rules forbid.

Both are the same error from opposite sides: a *single* assumed source of truth where the system has
**ownership domains**.

## 4. The missing layer

The fleet has no layer for *continuous* reconciliation. It is the only thing absent; everything else -
the topology, the contracts, the projections, the checks - is already sound. The target model
(see [model.md](model.md)) adds exactly that layer and gives the second truth a home, an owner and a
reconciler, without moving Nix below its floor or above its ceiling.

## 5. Non-goals

- **Not** replacing Nix with Kubernetes. The substrate, the network, the contracts and the checks stay.
- **Not** reconciling what does not need it. Slow, single-actor domains stay batch (invariant **R7**).
- **Not** a second configuration language. Desired state is still compiled by Nix where it is static;
  the reconciler owns only what is observed, derived or ephemeral.
- **Not** a per-domain reconciler. Domain logic is expressed as data on a generic engine
  ([architecture.md](architecture.md)).
