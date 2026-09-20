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

Username, display name and e-mail are **seeded once**: the entry carries `state: created`, so the object
exists after the first apply and everything about it afterwards belongs to the person and to whoever
administers identities in the interface. **Group membership is not declared at all** - it is the assignment
of people to policy and therefore people data, not configuration; see section 11 for the whole boundary. The **passkey cannot be**: FIDO2 is
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
  `authentik Admins`. Its password is `AUTHENTIK_BOOTSTRAP_PASSWORD` in the `services/authentik/core_env`
  secret; authentik consumes it only while `akadmin` does not exist, so it never resets a password that has
  already been changed. `infra-admins` is a **separate** cluster-admin group: the fleet's administrators
  are not the same set as Authentik's own administrators, and conflating them would make the identity
  system unable to lock anyone out of itself. To make a person a fleet administrator, put them into
  `infra-admins` in the interface - that single membership is the whole answer.
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

## 10. The directory

Authentik is the directory. It is served by the LDAP outpost on each of `hom-srv-01` and `cld-edge-01`
(389 plain, 636 TLS), and applications authenticate their users against it instead of keeping their own
accounts. Jellyfin is the first consumer; the mechanism is generic.

### 10.1 One declaration, no restatements

`contracts/directory` holds the structure of the directory for the whole fleet: the base DN, the user and
group subtrees, and the prefix of consumer service accounts. It is a contract module rather than a feature,
so it is loaded on every host and is not behind an enable flag. `usersDn` and `groupsDn` are derived from it.

A consumer never composes a DN. `contracts/endpoints` projects the resolved values into
`my.contracts.consumes.<service>.ldap` - the audience the service stated on its own endpoint, the SOPS path of
its app password (derived when the endpoint leaves it empty), and the bind DN. The provider creates its
accounts from the same contract, so both sides agree without reading each other's configuration. That matters
because provider and consumer normally run on different hosts: an earlier attempt published the bind DN from
the provider's feature and evaluated to an empty value on `hom-srv-01`, where Jellyfin runs.

### 10.2 What a consumer declares, and what it does not

A consumer states its **audience** once, on its endpoint:

```nix
ldap = {
  enable = true;
  accessGroups = [ "media-users" "infra-admins" ];
  adminGroups = [ "infra-admins" ];
};
```

That is policy, and it belongs to the service. The provider exposes identities and encodes no consumer's
policy - it does not know who may sign in anywhere. The compiler refuses a consumer that enables directory
authentication without naming `accessGroups`, because a service that authenticates against a directory
without stating its audience has no access policy.

### 10.3 How a bind is decided

The outpost runs the provider's bind flow, which authenticates with an app password, and then asks the core
whether that user may use the application. The application carries **no** policy binding, so it is open to
every user; the actual decision is the consumer's `memberOf` filter, which is why each service keeps deciding
its own audience. A service account whose role holds `search_full_directory` (an object permission on the
provider) may read the whole directory - Jellyfin needs that to find users at all - while an ordinary user
can only see their own entry. Jellyfin's login is verified end to end: `philipp` authenticates with his
Authentik password and is an administrator in Jellyfin because `infra-admins` is his group.

### 10.4 The client configuration is not state

Jellyfin's plugin reads one XML file from its state directory, and that file carries the bind password. It is
rendered from SOPS onto tmpfs and symlinked into place, so the password never reaches the store and the file
is read-only by construction. `restartTriggers` ties the service to the rendered file, because the plugin
loads its configuration once at start and nothing else would notice a change.

## 11. Who owns what: this repository, or the admin interface

Two authorities write into the same object store. The rule that keeps them apart is one sentence:

> **This repository owns the shape of the system. The interface owns the people in it.**

A fact has exactly one owner. It is never shared, and it never changes hands between the two: "first the
repository, then the interface" is how a declaration turns into a statement that is no longer true.

### 11.1 The interface may change

- **Users** — existence, name, address, password, avatar. People are not configuration.
- **Group membership** — who is in which group. Membership is the assignment of people to policy, and it is
  the access decision: a service accepts a group, a human decides who is in it.
- **Own credentials and devices** — app passwords, TOTP, WebAuthn, sessions. Nobody else can hold these; the
  bootstrap admin password exists here only as a hash.
- **Invitations** — an invitation link is a document, not system state.
- **Own profile attributes** — phone number for MFA, preferences.
- **Notifications** — "mail me when X happens" is an operational preference, not topology.

### 11.2 The interface may not change

Providers, applications, outposts, flows, stages, stage bindings, policies, roles, group *definitions*,
certificates, branding, sources, machine tokens and service accounts. Each of these is topology, policy or
integration, and all three have to be readable, reviewable and reproducible in the repository. A provider
added in the interface would be a second truth about the shape of the system.

The test for a new case is one question: **would I comment on this in a review?** If yes, it belongs in the
repository; if it only concerns a person, it belongs in the interface.

### 11.3 Two consequences that are easy to get wrong

**Group names are part of the shape.** Access hangs on them: every consumer's `memberOf` filter names the
groups it accepts. Renaming a group in the interface removes access for everyone without anything turning
red. Renaming a group in this repository means a new entry **and** `state: absent` for the old one — otherwise
the old name stays behind and can still grant access.

**Access runs only through membership.** There are no per-user application bindings, because that would be a
second mechanism next to the group filter — and two mechanisms are two truths. A service declares which groups
it accepts; a human is put into one of them.

### 11.4 Three kinds of fact, and what each one does

| Kind | Owner | Behaviour |
|---|---|---|
| declared, with a declared value | repository | a change in the interface is overwritten at the next apply — and the drift report says so **before** that happens |
| not declared | interface | it is never touched; it is reported as foreign, which is normal |
| declared, but the database value came from elsewhere | **defect** | the declaration is incomplete; a fresh install or a restore produces a different world and nothing notices - §11.6 is the inventory that closes it |

That third row is the only dangerous one, and it is not the interface's fault: it means we depend on a fact we
do not name. `token.managed`, `token.expiring` and `LDAPProvider.mfa_support` were three of them and are
closed - each is now declared with the value the serializer actually accepts (`practices.md` §6.11, §11.6
below). What remains in
§11.6 are dependencies on files and flags that are not model fields, each documented with its source.

### 11.5 The table: every model, its owner, and whether a human may change it

"Owner" is who writes the object's definition. "Relationships we set" are the links that come from a
blueprint; a relationship that is not listed is not ours. The last column answers "may I change X in the
interface?" in one sentence.

| Model | Object owner | Relationships we set | May a human change it? |
|---|---|---|---|
| `authentik_brands.brand` | repository | `flow_recovery` | no - topology and branding |
| `authentik_core.group` | repository | - | the definition: no. **Membership: yes** - that is an interface decision |
| `authentik_core.user` (people) | repository seeds existence | - (`groups` is deliberately absent) | yes - name, address, password, avatar, group membership |
| `authentik_core.user` (service account) | repository | `roles` | no |
| `authentik_core.token` (machine) | repository | `user`; fields `managed`, `expiring` | no - topology, and the key comes from SOPS |
| `authentik_rbac.role` | repository | `permissions` | no |
| `authentik_flows.flow` | repository | - | no |
| `authentik_flows.flowstagebinding` | repository | `target`, `stage`, `order` | no |
| `authentik_stages_*` (password, identification, user login, prompt, invitation, user write, email) | repository | - | no |
| `authentik_providers_*` (LDAP, OAuth2, proxy) | repository | flow fields, object `permissions` | no |
| `authentik_core.application` | repository | `provider`, `group`, launch URL | no |
| `authentik_outposts.outpost` | repository | `providers`, `permissions` | no |
| `authentik_policies.policybinding` | repository | `target`, `order`, policy/group/user | no |

The membership column is the line. A service declares which groups it accepts through its `memberOf` filter;
a human decides who is in those groups. There are no per-user application bindings, because a second mechanism
next to the group filter would be a second truth. The interface-only things from §11.1 - credentials and
devices, invitations, profile attributes, notifications - are not blueprinted at all and therefore appear in
no row of this table.

### 11.6 Facts we rely on but do not set

The rule from §11.4: a fact we depend on is either declared, or documented with the reason it cannot be.
This is the inventory that closes the third row. Every row here has been measured, not guessed.

| Fact | Where it comes from | Resolution |
|---|---|---|
| `LDAPProvider.mfa_support` | model default `true`; the database carried `true` | declared `false` in the provider builder - code-based MFA is meaningless for a bind account |
| `LDAPProvider.bind_mode`, `search_mode` | model default `direct` | declared `direct`, so their origin is the repository rather than a model default |
| `token.managed`, `token.expiring` | model defaults `NULL` and `true` | declared `null` and `false`; `managed` accepts only a non-empty string or NULL, and an expiring api token is rotated by authentik on its own schedule (see [`practices.md` §6.11](./practices.md)) |
| `Brand.branding_logo`, `branding_favicon`, `branding_custom_css` | names of files that must exist under `/var/lib/authentik/media` | provided by `features/system/theme`, which symlinks `logo.svg` and `theme.css` there through `systemd.tmpfiles`; the brand references them by name |
| `core_default_app_access` (`AppAccessWithoutBindings`) | tenant flag, default `true`, `authentik/core/apps.py`; read by `providers/ldap/api.py` | relied on: the LDAP application carries no binding, so it is open to every user and access is decided by the consumer's `memberOf` filter |

### 11.7 What this does not close

- **Direct SQL writes stay invisible.** No event, no blueprint. The rule "the database is not a change path"
  plus the event arm of the drift report are the only countermeasures.
- **Objects created in the interface that nobody declares are not reclaimed.** They are reported as foreign,
  which is the intended behaviour, not a gap.
- **A new consumer's SOPS secret is added by hand.** The endpoint contract derives the path; if the key is
  missing, `sops-install-secrets` fails the deploy loudly rather than starting with an empty credential.
- **The drift report compares scalar fields, not relationships.** A change to a provider list, a permission
  or a binding is not visible to the field diff; the apply's cardinal invariants still guard those.
- **A fresh install must create authentik's two unmanaged bootstrap tables** (`authentik_install_id`,
  `authentik_version_history`) before the first migration. authentik's own `server`/`worker` entrypoint (the
  Go binaries) does this on startup; the fresh-database acceptance test drove `ak migrate` plus a shell
  directly and therefore seeded them itself. No repository action follows from this.


