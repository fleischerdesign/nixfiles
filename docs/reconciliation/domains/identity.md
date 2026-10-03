# Domain: identity

> The first domain across the line, and the proof of the whole model: it is where declared policy and
> observed population meet. Owns [decisions/0005](../decisions/0005-identity-ownership.md); touches
> **R3**, **R4**, **R6**, **R10**, **R12**. References decisions **D7**, **D9**, **D12**.

## 1. Scope

| Half | Example | Class | Owner |
|---|---|---|---|
| Groups, roles, audiences | `ai-users`, `family` | declared | repository |
| Applications, providers, bindings | an Authentik application, a policy binding | declared | repository |
| OIDC / LDAP integrations | a client, an LDAP consumer | declared | repository |
| Users | a person created in the UI | observed | Authentik |
| Membership | a user added to a group | observed | Authentik |
| Per-member artifacts | a personal gateway, a per-user application | derived | reconciler |

## 2. Mechanism

1. A provider imports Authentik users and memberships as **observed** objects. It writes nothing back.
2. Compositions own the **declared** objects: groups, applications, OIDC/LDAP integrations and
   audience bindings, generated from the existing identity contract.
3. Derived artifacts are computed from declared policy and observed membership - a member of a group
   gets the artifact that policy grants the group, with no commit.

The declared side is the same material [`../../../contracts/identity/`](../../../contracts/identity/) already
projects into blueprints; the difference is that it is now reconciled continuously instead of applied
once ([decisions/0005](../decisions/0005-identity-ownership.md)).

## 3. Conflict semantics (D12)

Ownership is per field, so a conflict has a defined winner:

- A **declared** field edited in the UI is reverted and reported (**R11**). Declared means enforced.
- An **observed** field is never written, including when it disagrees with a stale snapshot.
- A field that is genuinely both must be split into two fields, not resolved case by case.

## 4. Lifecycle

- A user added in the UI: imported, and the group's derived artifacts appear.
- A user removed in the UI: the observed object disappears; the derived artifacts for that user are
  reaped per the class deletion policy, so no gateway, secret or backup outlives its owner
  (**R10**, **E6**).
- A group removed from Git: its declared objects are removed; users are untouched, because they were
  never Git-owned (**R4**).

## 5. The hard cases

| Case | Behaviour |
|---|---|
| Break-glass operator while Authentik is down | independent local admin, out of band (**D7**) |
| A provider with no first-party support | wrap the official Terraform provider, do not reimplement (**D9**) |
| A user in no declared group | observed, imported, granted nothing derived |
| A retired audience | tombstoned by policy, so access cannot silently return |
| Duplicate identity (two usernames, one person) | declared policy treats them as distinct; consolidating is a human decision, not a reconcile |

## 6. Boundary

The existing declarative identity core - the directory contract and the blueprint compiler - is platform
infrastructure and is never reconciled by the plane (**R1**). Only the population and the per-member
artifacts cross the line. If the provider is removed, the declared policy still exists in
[`../../../contracts/identity/`](../../../contracts/identity/) and the fleet returns to the
[identity.md](../../identity.md) specification's batch behaviour.

## 7. Checks

`reconciliation-preservation` (a UI user survives), `reconciliation-drift` (a declared group edited in
the UI is corrected and signalled), `reconciliation-orphans` (a removed user leaves no artifact). See
[checks.md](../checks.md).
