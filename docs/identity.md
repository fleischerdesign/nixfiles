# Identity, access and secrets

> **System:** Authentik · **Portal:** `auth.vyrx.de` · **Secrets:** SOPS with age · **Model:** zero trust
>
> Source of truth: `inventory/identity.nix`, the service contracts and the owned Authentik blueprints.
> The code is normative; where it and this text disagree, the code is right.

## 1. Model

No segment is trusted, including the house LAN - security is a property of every component, not a wall
at the edge. Zero trust (NIST SP 800-207), applied: **verify explicitly** (every access to an internal
resource carries a WireGuard key, a passkey assertion or an SSH key); **least privilege** (a service
account, a process and a person each hold what their task needs); **assume breach** (lateral movement is
limited by the trust lattice and by cryptographically addressed hosts).

The zones are partially ordered and the firewall implements the order rather than each rule separately.
They are addressing and policy on one Layer-2 segment ([architecture.md](architecture.md) §3):

```
Trust(guest) < Trust(iot) < Trust(mesh) <= Trust(corp) < Trust(infra)
```

The layers, from the outside in: identity and authentication (Authentik, passkeys); ingress (Caddy TLS,
CrowdSec, forward-auth); transport (WireGuard, ChaCha20-Poly1305, cryptokey routing); operating system
(NixOS hardening); storage and state (impermanence, restic); cryptographic material (SOPS with age).

## 2. Secrets

SOPS with age, one file (`secrets/secrets.yaml`), keys derived from identities that already exist.

| Key | Derived from | Used by |
|---|---|---|
| host key | the `/etc/ssh/ssh_host_ed25519_key` of the host, converted with `ssh-to-age` | every host decrypts its own secrets |
| operator key | `~/.config/sops/age/keys.txt` | break-glass, adding keys, user-level secrets in Home Manager |
| deploy keys | generated per purpose, authorised through `deployKeys` in the ssh feature | root access during deployment |

The system module decrypts as root with the host key; the Home Manager module decrypts as the user with
that key, because a user process cannot read a host key. Nothing is decrypted until a module declares a
secret. The operator key is a file, not a hardware token. No secret is passed on a command line, embedded
in the Nix store, or written into a generated configuration - the ESPHome engine assembles its
`secrets.yaml` in a private temporary directory and deletes it after the flash.

**Losing a device** is deterministic, because both places that matter are declared: remove the age key of
the lost host from `.sops.yaml`, run `sops updatekeys`, remove its WireGuard public key from
`my.topology`, and deploy the remaining hosts. The device keeps no mesh peer and no future secret. A
roaming client whose private key is escrowed under `infra/wireguard/<name>_private_key` must have that
key rotated or deleted in the same change, or the stale private half stays usable if it resurfaces.

**Missing secrets fail the build**: a module that references a path absent from `secrets/secrets.yaml`
fails evaluation, not deployment - the build is where a missing declaration is discovered.

## 3. Humans and machines are different kinds of thing

**Service accounts are fully declarative.** The account and its token are declared, and the token value
lives in SOPS: the blueprint creates the token object with a key read from the environment, and the
consuming service reads the same secret, so both sides meet on first boot with no interaction. The
direction is inverted on purpose - SOPS is the source of truth, so nothing is generated at runtime that
would have to be recovered later.

**People are seeded, not enforced.** An entry with `initialProfile` carries `state: created`, so display
name and e-mail are written when the account is first created and never again; everything afterwards -
credential, avatar, memberships the interface owns - belongs to the person. Infrastructure references use
the username as the stable key, so renaming that login means updating its declarations and consumers, not
treating it as a display-name change.

The inventory is not an exhaustive user list. People can be created in the interface or through
enrollment, and an entry with `initialProfile = null` references an existing UI-created person without
creating or modifying the account. The passkey cannot be declared: FIDO2 binds to a secure element and is
registered interactively. There are no enforced password policies, because the primary factor is a
passkey.

Groups use `my.directory.groups.<name>`: `members = null` leaves membership interface-owned, an explicit
list (including an explicitly empty one) is owned by the repository, and `state = "absent"` retires a
group - deleting an inventory entry alone is not a deletion request. Service audiences keep the reserved
`svc-` prefix and are derived, never declared by hand.

## 4. Who owns what

> **This repository owns the shape of the system. The interface owns the people in it.**

A fact has exactly one owner and never changes hands between the two. An entry is either **declared**
(`state: present` or `absent`: the repository enforces the field and the drift report names a
divergence) or **initialized** (`state: created`: a default for a new object, never enforced, never
drift). The two never mix on one entry, and
`features/services/authentik/lib/blueprints-check.py` enforces exactly that.

| Kind | Owner | Behaviour |
|---|---|---|
| declared, with a value | repository | a change in the interface is overwritten at the next apply, and the drift report says so before that happens |
| initialized, with a seeded value | repository writes it once | a default for a new object; the interface owns the field afterwards |
| not declared | interface | never touched, reported as foreign, which is normal |
| declared, but the database value came from elsewhere | defect | the declaration is incomplete; a fresh install or a restore produces a different world and nothing notices |

**The interface may change:** the own data of a person (name, address, password, avatar), which roles a
person has, their credentials and devices, invitations, own profile attributes, notifications.
**The interface may not change:** providers, applications, outposts, flows, stages, bindings, policies,
roles, group *definitions*, certificates, branding, sources, machine tokens and service accounts - each
is topology, policy or integration, and all three must be readable, reviewable and reproducible here. The
test for a new case is one question: would I comment on this in a review?

**Group names are part of the shape.** Access hangs on them - every consumer filter names the groups it
accepts - so renaming a group in the interface removes access for everyone without anything turning red.
A rename here means a new entry *and* `state: absent` for the old one. There are no per-user application
bindings, because a second mechanism next to the group filter would be a second truth.

**An audience a resource declares about itself is topology, and it is declared.** `accessUsers` names the
accounts a service belongs to; the contract turns each username into its own group and feeds it into
`accessGroups`, so the ingress, the directory filter and the portal read one value. `accessAuthenticated =
true` is the explicitly universal audience and excludes service accounts. A group-restricted publication
is projected into a `PolicyBinding` per group on the generated application, and the compiler refuses to
build a gated service that names no audience - an application with no binding is open to every
authenticated user.

## 5. Authentik constraints that cost real time

Properties of Authentik, not of this repository.

| Constraint | Consequence |
|---|---|
| Blueprint YAML knows `!KeyOf`, `!Find`, `!Env`, `!File`, `!Context` - not `!Key` | an unknown tag breaks the migration that parses every blueprint; the whole server fails to start |
| Only `*.yaml` is discovered | structured references are rendered as native tagged YAML, not string replacement |
| Blueprint application is unordered | dependencies must be declared explicitly with `metaapplyblueprint` |
| `authorization_flow` and `invalidation_flow` are both required on a provider | a provider without them fails at apply time, not at parse time |
| `redirect_uris` are objects (`{matching_mode, url}`), not strings | a plain string list is silently ignored |
| The worker deadlocks on `authentik_flows_stage` during a fresh bootstrap if it runs multi-threaded | `AUTHENTIK_WORKER__THREADS=1`, unconditionally |
| There is no out-of-band setup wizard | `AUTHENTIK_BOOTSTRAP_PASSWORD` triggers `system/bootstrap.yaml`, which creates `akadmin` and sets `setup = true` |
| No two hosts may declare the same OIDC publication name, and no two integrations may share a client ID | both are asserted at evaluation time, naming the collision |

## 6. Bootstrap, enrollment, self-service

`akadmin` is the only account that can always get in, and it belongs to `authentik Admins`; its password is
`AUTHENTIK_BOOTSTRAP_PASSWORD`, consumed only while `akadmin` does not exist, so it never resets a changed
password. It is break-glass and not a member: superusers do not bypass application policy bindings, so it
reaches no service unless a group grants it. Enrollment creates people through invitations and assigns
the interface-owned `media-users` group; e-mail recovery, invitation enrollment, passkey autofill
(conditional UI) and remember-me are wired through the brand.

## 7. The directory

Authentik is the directory, served by an LDAP outpost on `hom-srv-01` and `cld-edge-01` (389 plain, 636
TLS); applications authenticate their users against it instead of keeping their own accounts.
`contracts/directory` holds the structure for the whole fleet - base DN, user and group subtrees, the
prefix of consumer service accounts - as a contract module, so it is loaded everywhere and is not behind
an enable flag. A consumer never composes a DN: `contracts/identity` projects the resolved values into
`my.contracts.consumes.<service>.ldap`, and the provider creates its accounts from the same contract.

A consumer states its audience once, on its own publication:

```nix
publications.web = {
  endpoint = "web";
  subdomain = "jellyfin";
  accessGroups = [ "media-users" "infra-admins" ];
  adminGroups = [ "infra-admins" ];
};
identity.ldap.directory = {
  publication = "web";
  enable = true;
};
```

The provider exposes identities and encodes no consumer policy - it does not know who may sign in
anywhere. The compiler refuses a consumer that enables directory authentication without naming
`accessGroups`, because a service that authenticates against a directory without stating its audience has
no access policy. The application itself carries no policy binding, so it is open to every user; the
actual decision is the `memberOf` filter of the consumer. A service account whose role holds
`search_full_directory` may read the whole directory.

**Two outpost models, deliberately.** Forward-auth uses the **embedded** outpost inside the Authentik
server - a per-request decision the server makes itself, reached at `127.0.0.1:9055` on the server and
`10.10.100.1:9055` from LAN hosts; a separate process would add latency and a credential for nothing.
LDAP is a long-lived TCP service and runs one outpost **per host** that needs it, with a service account
token read from SOPS; its role carries global read permissions bound to a **named** role, not the managed
one, which upgrades recreate. The central listener admits only the hosts that consume it, derived from
the Caddy routes and the outposts; an empty consumer set does not mean all trust levels.

A consumer that needs the directory reads one XML file from its state directory, rendered from SOPS onto
tmpfs and symlinked into place, so the bind password never reaches the store; `restartTriggers` ties the
service to the rendered file, because the plugin loads its configuration once at start.

## 8. Operating system hardening

`features/system/security` is part of the base role on every host: `slab_nomerge`,
`page_alloc.shuffle=1`, `kernel.kptr_restrict = 2`, `kernel.dmesg_restrict = 1`,
`kernel.unprivileged_bpf_disabled = 1`, `tcp_syncookies = 1`, strict `rp_filter`, no ICMP redirects.
All are chosen for zero runtime cost.

systemd sandboxing (`ProtectSystem = "strict"`, `ProtectHome`, `PrivateTmp`, `PrivateDevices`,
`NoNewPrivileges`, `ProtectKernel*`, `RestrictNamespaces`, empty `CapabilityBoundingSet`) is a declared
contract that the service modules do not yet carry: measured 2026-09-20, none of the 35 service modules
sets any of these, so the hardening in place is the kernel baseline above. Enforcing the sandbox is a
per-service change with a real cost, because `ProtectSystem = "strict"` breaks any service that writes
outside its declared state and cache directories - the fix is to declare those directories, not to relax
the sandbox.

## 9. Access

- **SSH.** The cloud hosts accept SSH on their **public** address - the lifeline that survives a broken
  mesh, a bad route or a lockout - and every other host listens on its LAN and overlay address only.
  Keys only (`PasswordAuthentication = false`, no password root login, Ed25519 throughout), two keys
  fleet-wide: the operator key and the fleet deploy key. `~/.ssh/deploy-key` is the node tunnel secret
  and never addresses a fleet host. sshd binds explicitly and waits for the units that create the
  addresses, because it reads its `ListenAddress` list once at startup.
- **Deployment** is not coupled to health probes: a rebuild must be fast and atomic, and health is
  observed asynchronously by the monitoring stack, which alerts independently of who deployed what. What
  is verified before a switch is that the replacement path exists (see [operations.md](operations.md)).
- **The ingress is the only public surface.** A service that declares `scope = "public"` is proxied; one
  that does not is not reachable from outside. Certificates are per name, issued on the host that
  terminates them ([architecture.md](architecture.md) §5.3).

## 10. Audit

Journal, Caddy access logs and CrowdSec decisions are shipped to Loki on `cld-edge-01`, so a compromised
host cannot erase what has already left it. A failed unit is part of the health check - a backup that
fails silently is a backup that does not exist.

## 11. Outbound application mail

`inventory/smtp.nix` assigns the shared transport (`mail-eu.smtp2go.com`, port `2525`, STARTTLS, from
`noreply@<domain>`); `features/system/smtp` declares the credentials, and each enabled consumer enables
the shared declarations, so a host that consumes no mail materialises none. Delivery is verified by
sending to a mailbox under your control and reading the SPF, DKIM and DMARC results in the received
headers: SMTP acceptance alone does not prove inbox delivery. Authentik uses the global transport, and
its sender must belong to the verified domain.
