# Migration

> How each domain crosses the line, one at a time, reversibly. This is the repository's first
> non-negotiable applied to the architecture: the replacement is proven before the original is
> deleted, and the proof is measured at the consumer.

## 1. Principles

1. **One domain at a time.** A domain crosses only when its **D**-decisions are closed and its
   invariants have checks ([checks.md](checks.md)).
2. **Proof before deletion.** The domain runs under Nix and under the reconciler in parallel until the
   reconciler's output is measured equal where it should be equal, and correctly different where it is
   observed.
3. **Reversibility.** Every step removes only what it added. The exit is the plan's
   [D14](edge-cases.md).
4. **Verification per host class.** A domain verified on `cld-ops-01` is not verified on `hom-srv-01`.
5. **No mixed ownership.** A domain is never half declared and half observed at the object level; the
   split is by field ([ownership.md](ownership.md) §1).

## 2. The move pattern

For a single domain, in order:

1. **Declare the schema** - the `kind` (XRD) and its composition, as a build-time artifact.
2. **Import, do not create** - adopt existing external objects as observed; assert no write occurred.
3. **Shadow** - render the domain's artifacts from the reconciler while Nix still owns them; diff.
4. **Cut over the declared half** - the reconciler owns policy fields; observed fields stay untouched.
5. **Delete the Nix path** only after the shadow period is clean.
6. **Record the baseline** for the domain, and its exit criterion.

Steps 1-3 are read-only or additive. The only step that changes ownership is 4, and it is the one with
a measured acceptance test.

## 3. Domain order

Identity is first because it is the hardest and the most valuable: if the ownership split works for
users created in a UI, it works for everything. The order is by difficulty, not by excitement.

| Order | Domain | Why here | Prerequisites |
|---|---|---|---|
| 1 | Identity | hardest split (policy vs population); unblocks per-owner workloads | D7, D9, D12 |
| 2 | Workloads | generalizes OpenClaw; needs identity's membership | D11, D13, isolation classes |
| 3 | Exposure (init, DNS, TLS) | dynamic names need internal DNS and gated issuance | D2, D3 |
| 4 | Data | tenant DB/volumes; deletion and retention are dangerous | D5, D11 |
| 5 | Backup | the runtime counterpart of the backup contract | D5 |
| 6 | Observability | dynamic targets must be seen | D4 |
| 7 | Secrets | the bridge is shared; it lands once the consumers exist | D10 |

## 4. Adopting existing entities

The fleet already has objects the reconciler will touch: Authentik applications, DNS records, per-user
gateways. None is recreated. Each is imported, labelled, and only then owned field by field
([bootstrap.md](bootstrap.md) §3). An import that shows a delete or a recreate in its plan is refused.

## 5. Rollback per domain

| Domain | Rollback |
|---|---|
| Identity | reconcile an empty declared set; declared artifacts removed, observed users remain |
| Workloads | delete the `kind`; instances reaped by policy; Nix path restored if needed |
| Exposure | revert to the declared wildcard; dynamic names stop being minted |
| Data | reconcile the database/volume out of scope; **orphan, never cascade**, until proven |
| Backup | reconcile the derived job away; snapshots retained per policy |
| Observability | remove service discovery; static targets remain |
| Secrets | revoke entity secrets; platform secrets untouched |

## 6. Graduation

When **D1..D14** are decided and every domain is either moved or explicitly retained, this package
graduates: its normative content is folded into [`../architecture.md`](../architecture.md),
[`../identity.md`](../identity.md), [`../naming.md`](../naming.md) and [`../security.md`](../security.md),
and the package is deleted. A plan that outlives its implementation describes two states at once; the
repository forbids that, and this plan obeys it.

## 7. What never moves

For the avoidance of doubt, the following remain Nix and are never reconciled by the plane (**R1**,
**R7**): the substrate, the network and WireGuard mesh, the firewall and trust zones, DNS resolution
infrastructure, the ingress engine, mail, the media stack, the desktop and notebook clients, and the
IoT/hardware devices. They are listed again here only because a migration document that leaves the
boundary implicit is a migration document that will drift.
