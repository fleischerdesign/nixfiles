# Glossary

> Terms are defined once, here. Other documents use them without redefining. Where a term collides with
> an existing one in [`../architecture.md`](../architecture.md) (zone, plane, contract, scope), that
> document's definition wins.

**Actuator.** The thing that actually runs a reconciled intent: a pod, a virtual machine, a systemd
unit, or an external API call.

**Adoption.** The step in which a control plane takes over objects that already exist, by importing
them rather than recreating them. The opposite of creation; the reason bootstrap is not a one-shot.

**Batch reconciliation.** A desired state is evaluated and applied once (Nix, Terraform). Between runs
there is no loop, so drift is unseen. Contrast **continuous reconciliation**.

**Composition.** A declarative mapping from one object to many, executed by a generic engine. Lets a
`Gateway` become a Deployment, Service, Ingress, Secret and backup object without writing a controller.
The Crossplane term; see [architecture.md](architecture.md) §3.

**Continuous reconciliation.** A long-running loop that reads desired and observed state and converges
them, triggered by events and by a periodic resync (Kubernetes, operators). Contrast **batch
reconciliation**.

**Control plane.** Here: the component that owns run-time entities and reconciles them. Not "the
Kubernetes control plane" specifically; the role is what matters.

**Declared state.** A fact whose source is Git, evaluated purely by Nix. Owned by the repository. One
of the three state classes in [model.md](model.md).

**Derived state.** A pure function of declared and observed state, recomputed on each reconcile. Owned
by the reconciler.

**Drift.** Divergence between derived and actual state. A first-class, measurable signal (**R11**), not
a log line.

**Edge-triggered.** A reaction caused by an event. Fast, but insufficient alone; see **level-triggered**.

**Finalizer.** A marker that delays deletion of an object until its owner has cleaned up external
resources. The mechanism behind **R10**.

**Import-from-derivation (IFD).** A Nix feature that evaluates a derivation's output during
evaluation. Refused against mutable sources here, because it makes evaluation depend on the run time
(**R2**).

**Kubernetes Resource Model (KRM).** The general pattern - typed objects with a spec, a status and
owners, reconciled by controllers - independent of any particular cluster.

**Level-triggered.** A reaction caused by observing state, not by an event. Guarantees convergence even
when an event is lost (**R5**).

**Line of Dynamism.** The boundary between the declarative (batch) and runtime (continuous) zones, as
drawn in [model.md](model.md) §3.

**Observed state.** A fact whose source is the runtime (a UI-created user, a live instance). Owned by
the system that produced it, imported but never overwritten (**R4**).

**On-demand TLS.** Certificate issuance triggered by the first request for a name, rather than by a
declared list. Powerful for dynamic names; a resource-exhaustion vector if ungated (**D3**).

**Owned / Observed (labels).** The two ownership labels applied to objects, plus `derived`. See
[ownership.md](ownership.md) §1.

**Provider.** A reusable translation between an external API and objects (Authentik, Cloudflare, SQL).
Generic and API-shaped, as opposed to a per-use-case controller.

**Reconcile.** The idempotent act of making actual state match derived state. Idempotent and
order-independent (**R5**).

**Seed.** The Nix-installed bootstrap of the control plane, before adoption; the answer to the
chicken-and-egg problem (**R1**).

**Server-side apply (SSA).** Kubernetes' field-ownership model, generalised here to per-field ownership
across owners (**R3**).

**Split-horizon DNS.** One name answers differently on different planes (public vs internal). A naming
rule; its dynamic-name counterpart is **D2**.

**Stratification.** The invariant that no layer is reconciled by a layer depending on it; concretely,
the control plane never manages its own substrate, network, firewall or authenticating identity
(**R1**).

**XRD.** A composite resource definition: the schema of a new `kind` the engine serves. The extension
point that lets a `Gateway` be an object without new code.
