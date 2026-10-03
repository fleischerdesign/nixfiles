# Roadmap

> A phased adoption with a defined exit. The repository's non-negotiables govern this plan:
> prove the replacement before deleting the original ([`../../AGENTS.md`](../../AGENTS.md)), a check
> must be able to fail loudly, and the expectation is written next to the measurement. No phase is
> entered before its predecessor's exit criteria are met.

## 0. Guardrails

1. **Nothing is deleted to make room.** The reconciler runs *beside* the Nix-only fleet until proven
   (**R7**, **D14**).
2. **Every phase has an observable exit criterion** and a rollback that removes only the phase's
   additions.
3. **Verification is per host class** - cloud server, home server, desktop, notebook - and read at the
   consumer, not the builder.
4. **A phase that cannot state its falsifier does not start.** Each criterion below names what would
   show it false.

## 1. Phase 0 - Spec, measurement, inert control plane

Bring the layer into existence without giving it authority.

- This design package is reviewed and its **D1..D14** decisions are closed or explicitly deferred.
- The control plane (k3s) is installed as a **NixOS feature on one host**, mesh-only, with Traefik,
  service-LB and local-storage disabled, and **no reconciliation authority**.
- Measurements, expectation written beside each:
  - `/dev/kvm` and `systemd-detect-virt` per host class -> which hosts can host VM actuators (**D1**).
  - actual churn and actor count for the candidate domains -> whether the fleet clears the threshold
    (**D8**, **R7**).
  - the effect of k3s on the host: cgroups, nftables tables, CoreDNS, NodePorts, and whether the
    exposure audit sees new listeners that no contract declared.

**Exit:** the control plane runs, is reachable only over the mesh, and changes nothing. **Falsified if**
any static service's behaviour changes, or a listening socket appears that is not a decision.

**Rollback:** disable the feature; the host is byte-for-byte the previous generation.

## 2. Phase 1 - Identity, observed only

Prove that the second truth can be read without being touched.

- A provider imports Authentik users and memberships as **observed** objects. It writes nothing back.
- Expectation: the imported set equals the real directory, including users created in the UI that no
  Nix file references.
- The result is diffed against the directory contract's declared projection, so the *delta* between
  declared policy and observed reality is a measured number, not a belief.

**Exit:** the observed set matches the directory, repeatably, in read-only mode; the delta is explained.
**Falsified by** any write to Authentik, or any drift between two consecutive imports.

**Rollback:** stop the provider; nothing was written.

## 3. Phase 2 - Identity, policy owned

Move policy across the line, entities not.

- Compositions reconcile the **declared** half - groups, bindings, audience, application objects -
  from Nix-rendered desired state.
- **R4** is the acceptance test: a UI-created user survives every reconcile.
- A deliberate drift is introduced (a declared group changed in the UI) and must be corrected and
  reported (**R11**), not silently accepted.

**Exit:** declared policy converges; observed entities are never overwritten; drift is detected and
signalled. **Falsified by** a vanished UI user or an uncorrected declared drift.

**Rollback:** reconcile an empty desired set; declared artifacts are removed, entities remain.

## 4. Phase 3 - One workload domain

Prove the full lifecycle on a single `kind`, generalising OpenClaw rather than special-casing it.

The `kind` (working name `Gateway`) must demonstrate, in one pass:

- creation derived from observed membership (S2);
- an ephemeral sibling with a TTL and an isolation class (S3);
- its own telemetry target, visible in the platform Prometheus (**D4**, S10);
- its own backup class with a deletion policy (**D10**, S11);
- its own entity secret via the bridge (**D10**, S12);
- its own name, resolved internally and externally (**D2**), with TLS inside the wildcard (**D3**);
- teardown that leaves no orphan: no name, no secret, no snapshot, no database (**R10**, E6).

**Exit:** the four lifecycle facts above hold for create, health, inactivity and delete, in both the
cloud and home host classes. **Falsified by** any orphan after delete, or any workload invisible to
telemetry.

**Rollback:** delete the `kind` and its class; reconciliation stops, nothing static is affected.

## 4b. After Phase 3

Only after Phase 3 does the reconciler govern additional domains, and only domains that clear **R7**.
The program is complete when **D1..D14** are decided and no domain in the matrix of
[ownership.md](ownership.md) is marked *gap*.

## 5. Definition of done

1. Every decision **D1..D14** is decided and recorded; every scenario **S1..S16** has a stated home.
2. Every invariant **R1..R12** has a check that can fail loudly, in the style of
   [`../../checks/`](../../checks/): a fixture, an assertion, and a measurement at the consumer.
3. The static fleet boots and serves with the control plane stopped (**R8**).
4. The exit path (**D14**) is exercised once, into a throwaway environment, before the plan is
   considered proven.
5. This package is folded into the present-state specification and deleted; a plan that outlives its
   implementation describes two states at once.

## 6. Per-host-class verification

| Class | Hosts | What must hold |
|---|---|---|
| Cloud server | `cld-edge-01`, `cld-ops-01` | API mesh-only; no public listener; provider egress as declared |
| Home server | `hom-srv-01` | KVM availability measured; home-only and internal scopes respected |
| Desktop | `hom-wrk-01` | consumer only; never a control-plane member |
| Notebook | `mob-nb-01` | roaming; degraded mode behaves identically offline |

A criterion measured on one class says nothing about another; each is read at the consumer, on its own
host, with the expectation stated first.
