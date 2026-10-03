# Domain: secrets

> Secrets for entities do not exist in Git, so they need a second store and a single, auditable bridge.
> Owns [decisions/0010](../decisions/0010-secrets-two-store-bridge.md); touches **R2**, **R10**,
> **R12**. References decision **D10**.

## 1. Two stores, one bridge

| Secret | Store | In Git | Rotation |
|---|---|---|---|
| Platform (SOPS) | SOPS, encrypted | yes (ciphertext) | declared, by commit |
| Entity (per instance) | control-plane store | no | policy or event |
| The bridge | one operator | the operator's config only | n/a |

The bridge is the **only** place the two stores meet: a platform secret can be surfaced into the plane,
and an entity secret can be surfaced to a host unit, without either store learning about the other's
internals. A second, silent path - reading SOPS from inside a workload, or writing an entity secret
back into Git - is a defect (**D10**).

## 2. Properties

- **No secret in rendered output.** Nix-rendered manifests, plans and logs carry references, never
  values. A value that appears in any of them fails the build ([testing.md](../testing.md) §3).
- **Scoped.** A workload reads only its own entity secrets; a provider holds only its domain's external
  credential (**R12**).
- **Short-lived where possible.** Tokens that can expire, do; passwords that cannot are rotated on a
  declared schedule.
- **Revocable.** Deleting an entity revokes its secrets as part of its deletion policy (**R10**); an
  orphaned secret is an orphan like any other (**E6**, **E13**).

## 3. Consumption

A host unit needs a value the plane holds. The bridge surfaces it by the mechanism the unit already
uses - a file, an environment reference - so the unit does not learn a second secret system. The
concrete mechanism is a decision; the invariant is that there is exactly one bridge.

## 4. Threat

The entity store is inside the highest-value asset (**E1**): stealing it compromises every tenant. It
is therefore encrypted at rest, reachable only from the mesh, readable only by the namespaces that own
the value, and audited. Break-glass applies ([security.md](../security.md) §4): an operator who cannot
authenticate through Authentik can still revoke a secret.

## 5. Boundary

Platform secrets remain entirely in SOPS and Nix, untouched by this domain. Only entity secrets cross
the line. Removing the layer leaves SOPS intact and requires revoking entity secrets per the deletion
policy.

## 6. Checks

A build check that no rendered output contains a secret value; a preservation check that an entity
secret survives a reconcile and is revoked on delete; a scoping check that one namespace cannot read
another's secret. See [checks.md](../checks.md).
