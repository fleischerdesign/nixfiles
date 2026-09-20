# Identity and access

> **System:** Authentik · **Portal:** `auth.vyrx.de` · **Font of truth:** the blueprint files in
> `features/services/authentik/server/blueprints/` plus the generated ones
>
> This document records how identity works here **and** the constraints that were expensive to learn.
> The code is normative; where it and this text disagree, the code is right.

## 1. The GitOps axiom

Authentik's PostgreSQL database is **ephemeral runtime state**. Every provider, outpost, group, service
account, role binding and application is declarative code in this repository, applied idempotently when
the server starts. Losing the database costs a restart, not an afternoon of clicking.

The reason is not elegance: an identity system configured through a web UI is the one component whose
configuration cannot be reconstructed from the repository, and it is the component that gates
everything else.

## 2. Layout

```
features/services/authentik/
├── server/blueprints/            hand-written, applied in name order
│   ├── 00-system/brand.yaml      title, design tokens, favicon
│   ├── 01-rbac/users-and-groups.yaml
│   └── 02-flows/                 enrollment, recovery, remember-me, passkey autofill
├── server/default.nix            runtime + the blueprint compiler
├── outpost/proxy/                per-host forward-auth where the embedded outpost cannot reach
└── outpost/ldap/                 per-host LDAP outposts
```

`03-apps/*.yaml` (`proxy-apps-generated.yaml`, `oidc-apps-generated.yaml`,
`ldap-outposts-generated.yaml`) does not exist in the tree: the compiler in `server/default.nix` emits
it **from the service contracts** - every service that declares an OIDC or forward-auth endpoint gets a
provider and an application without writing any blueprint. That is the whole point of the contract
layer - see [architecture.md](architecture.md) §6.1.

## 3. Constraints that cost real time

Recorded because they are properties of Authentik, not of this repository, and each one was found the
hard way.

| Constraint | Consequence |
|---|---|
| Authentik's blueprint YAML knows `!KeyOf`, `!Find`, `!Env`, `!File`, `!Context` - **not `!Key`** | an unknown tag breaks the `authentik_blueprints.0001_initial` migration, which parses every blueprint; the failure appears as the whole server failing to start |
| Only `*.yaml` is discovered; JSON cannot carry YAML tags | generated blueprints are emitted as tagged YAML through a sentinel-and-rewrite step, not as JSON |
| Blueprint application is **unordered** | dependencies must be declared explicitly with `authentik_blueprints.metaapplyblueprint` - the default provider flows and the RBAC group are declared that way |
| `authorization_flow` **and** `invalidation_flow` are both required on a provider | a provider without them fails at apply time, not at parse time |
| `redirect_uris` are objects (`{matching_mode, url}`), not strings | a plain string list is silently ignored |
| The worker deadlocks on `authentik_flows_stage` during a fresh bootstrap when it runs multi-threaded | `AUTHENTIK_WORKER__THREADS=1`, unconditionally |
| There is no out-of-band setup wizard | `AUTHENTIK_BOOTSTRAP_PASSWORD` triggers `system/bootstrap.yaml`, which creates `akadmin` and sets `setup = true` |
| Two hosts may not declare the same OIDC endpoint name | the module asserts it at evaluation time and names the collision |

## 4. Humans and machines are different kinds of thing

### 4.1 Service accounts - fully declarative

For daemons, outposts, pipelines and APIs. The account and its token are both declared, and the token's
*value* comes from SOPS: the blueprint creates the token object with a key read from the environment,
and the consuming service reads the same secret. Neither side needs a human.

`ServiceAccount = (username, role, token_from_SOPS)`

### 4.2 People - the shell is declarative, the credential is not

Username, display name, e-mail and group membership are declared. The **passkey cannot be**: FIDO2 is
bound to a secure element and created through an interactive challenge-response ceremony in the
browser. A person therefore exists immediately with every right they will have, and registers their
passkey at first login through the standard WebAuthn flow.

There are no enforced password policies: the primary factor is a passkey, and a policy that only
constrains the fallback path would be friction without security.

## 5. Two outpost models, deliberately

| | Forward-auth | LDAP |
|---|---|---|
| What it is | the **embedded** outpost inside the Authentik server | one outpost **per host** that needs it |
| Why | forward-auth is a per-request decision the server can make itself; a separate process adds latency and a token for nothing | LDAP is a long-lived TCP service; it belongs where the consumer is |
| Address | `my.features.services.authentik.server.embeddedOutpostAddress` - `127.0.0.1:9055` on the server, `10.10.100.1:9055` from the LAN hosts over the mesh | per host, listening on 389/636 |
| Credential | none | a service account plus a token with `intent = "api"`, read via `!File` from `services/authentik/outposts/<host>-ldap-token` |

The LDAP outpost's role carries global read permissions (`view_user`, `view_group`, `add_event`) and
object permissions bound to a **named** role - not to the managed role, which is recreated by upgrades.

An earlier version of this document described a separate proxy outpost with its own token. That is not
the design: the embedded outpost is the design, and it removes a credential and a process.

## 6. Token inversion

The naive order is: create the outpost in the UI, let Authentik generate a token, copy it into SOPS.
That makes SOPS a copy of a value that already exists elsewhere, and it cannot be rebuilt from the
repository.

The direction is inverted - **SOPS is the single source of truth**:

1. the token exists in `secrets/secrets.yaml`;
2. the server's environment is populated from it;
3. the blueprint creates the token object whose key is that value (`key: "!Env …"`);
4. the outpost starts with the same value from the same file;
5. both sides meet on first boot, with no interaction.

Nothing is generated at runtime that would have to be recovered later.

## 7. Bootstrap and self-service

- **No OOBE.** The bootstrap password in `services/authentik/core_env` drives `system/bootstrap.yaml`,
  which creates `akadmin` and marks setup complete.
- **Break-glass.** `akadmin` is the only account that can always get in, and it belongs to
  `authentik Admins`. `infra-admins` is a **separate** cluster-admin group: the fleet's administrators
  are not the same set as Authentik's own administrators, and conflating them would make the identity
  system unable to lock anyone out of itself.
- **Family accounts** (`family`, `media-users`) are created through the enrollment invitation and carry
  no password until they register a passkey.
- **Self-service:** e-mail recovery wired to the brand, invitation enrollment, passkey autofill
  (conditional UI) and remember-me (`session_duration = 7 days`, `remember_me_offset = 30 days`).

## 8. Applying changes

Blueprints are part of the **host closure**: `nixos-rebuild switch --flake .#cld-edge-01` (or
`nod switch cld-edge-01`). There is no separate reconciler target for Authentik - the server applies
what its closure contains. See [operations.md](operations.md).

## 9. What this buys, honestly

| Situation | Before | Now |
|---|---|---|
| database lost | every client, token and outpost clicked back by hand | restart: the blueprints are applied idempotently |
| new service | provider, redirect URI and secret by hand | the service declares an endpoint; the provider is generated |
| new outpost | token generated in the UI, copied into SOPS | the token already exists; the outpost reads it |
| "who may access what" | visible only in database rows | a Git commit, reviewable |

Recovery time after a database loss is **not measured**. What is known is that the blueprints are
applied on start and that their dependencies are declared; how long that takes on the actual hardware
has not been timed, so no number is claimed here.
