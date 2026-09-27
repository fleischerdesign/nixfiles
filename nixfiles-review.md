# Nixfiles architecture and engineering review

Review date: 2026-09-27. Baseline: `2117838f3e67125d769b31447125094a9fb4160b`.

File references in the findings name the **reviewed revision**: later increments renamed `default.nix`
to `nixos.nix`, split `lib/audit` into `apps/`, and moved `lib/nftables.nix`, so a path quoted as
evidence may be a revision behind the tree. The finding is still about the revision it names.

This is the explicitly requested, point-in-time assessment and improvement plan. It is kept outside
`docs/`, whose stated purpose is the specification of the current system. Implementation work should
turn the work packages below into issues or commits and update the relevant present-state specifications.
This review is not a second architectural source of truth.

The follow-up on repository organization and discovery is incorporated as **F25-F35**, **WP7** and
**section 9**. It includes executed discovery fixtures and evaluation measurements, alongside a concrete
folder/naming convention proposal. **Section 9.9** classifies individual files by responsibility and
explains the proposed split of `lib/nftables.nix`. The reviewed source revision is unchanged.

## 1. Executive assessment

**The repository has a strong architectural foundation, but its guarantees are less complete than its
interfaces and documentation suggest.** It should be improved incrementally, not replaced with another
configuration framework.

The best existing idea is the declaration-to-projection pipeline: services declare capabilities and
the platform derives names, proxy configuration, policy and monitoring. Typed options, role composition,
central address selection, SOPS integration and fleet evaluation are all valuable. The host matrix is
already derived rather than maintained separately.

The principal problem is **semantic completeness**:

- Some accepted contract fields have no executing consumer.
- Some checks accept configurations that contradict the property they claim to verify.
- Several generic-looking options only work with today's defaults.
- Monitoring currently generates HTTP probes for SSH, WireGuard and other non-HTTP endpoints.
- Backup declarations do not yet establish complete coverage or recoverability.
- Documentation makes stronger claims about isolation, failover and implementation coverage than the
  reviewed code supports.

The highest-value modernization is therefore to make every supported declaration meaningful and every
important guarantee falsifiable. Rearranging directories comes afterwards.

### Quality dimensions

| Dimension | Assessment | Main reason |
|---|---|---|
| Professional / evidence-based | Strong intent; uneven execution | Full checks pass, but targeted counterexamples expose missed defects |
| Clean / comprehensible | Good outer structure; overloaded internals | Roles and feature entry points are readable; contracts mix unrelated responsibilities |
| DRY | Good direction; incomplete fact ownership | Some addresses/providers and several interpretations of contracts are repeated |
| SOLID, adapted to Nix | Dependency inversion exists; interface segregation needs work | Service contracts help, but broad schemas and provider-specific details leak across boundaries |
| Consistency | Material improvement needed | Documentation, option descriptions, defaults and rendered behavior disagree in concrete places |
| Agnosticism / portability | Fleet-specific with reusable parts | Host names, interface names, user discovery and one architecture remain embedded assumptions |
| Reliability | Useful baseline; insufficient negative coverage | Evaluation is broad, but runtime semantics and restore behavior are not established by it |

These are qualitative judgments, not measured numerical scores or a certification.

## 2. Method, scope and measured baseline

### What was inspected

- Flake assembly, module discovery, system builder, roles and host composition.
- All seven contract modules and the topology model.
- DNS, WireGuard, Caddy, database, backup, identity and monitoring projections.
- Representative application modules, user construction and Home Manager wiring.
- CI, update workflow, developer hook, package overlays and audit helpers.
- Architecture, engineering practices and security specifications.

Tracked source contains **148 Nix files, 19,672 Nix lines** at the baseline. This is a cross-cutting
architecture review with targeted implementation inspection, not a line-by-line verification of every
package, reconciler, application or upstream dependency.

### Evidence levels used below

- **Measured:** a local command or isolated counterexample was executed during this review.
- **Source-confirmed:** a declaration and its relevant readers were inspected; the conclusion follows
  from those source paths.
- **Design recommendation:** a proposed improvement, not a claim that production is currently broken.

### Executed checks

| Measurement | Expected result | Observed result |
|---|---|---|
| `git status --short`, before work | Identify pre-existing changes | Clean checkout |
| `nix flake check --no-build --no-update-lock-file` | All current hosts and check derivations evaluate | Passed for all five hosts |
| `nix flake check --no-update-lock-file --print-build-logs` | All declared checks succeed | All nine checks passed |
| Force `deploy.nodes.cld-edge-01.profiles.system.path` | An exported deployment path evaluates | Failed: `attribute 'deploy-rs' missing` |
| Add a non-null backup pre-dump hook through `extendModules` | A supported hook compiles | Failed: `backupPreparePrune` does not exist |
| Give one synthetic endpoint another endpoint's canonical name as an alias | Naming I2 rejects the collision | No naming assertion failed |
| Replace the LAN router's forwarding `accept` verdicts with `drop` in a synthetic check input | Reachability invariants reject the mutation | Baseline and mutated violations both `[]` |
| Evaluate generated Prometheus local HTTP targets | Only valid HTTP(S) targets with declared health paths | Includes HTTP to ports 22, 51820, 4369 and 9443; Sonarr uses `/`, not `/ping` |
| Evaluate backup enablement and paths per host | Explicit coverage can be inspected | Restic enabled on edge and home server; disabled on ops and both personal machines |

Warnings were retained: LibreOffice's old package naming emitted two warnings; Nix also warned about
the custom `deploy` and `nodTargets` outputs. A custom output warning alone is not a defect. The forced
evaluation failure of `deploy` is a defect.

The nine checks include statix and deadnix. Their standalone executables were not initially on `PATH`;
they were exercised through the pinned flake checks. Full NixOS closures for all five machines were not
built by this review: `eval-hosts` deliberately evaluates derivation paths without building the hosts.
No live fleet probes, activation, restore, decryption or secret modification was performed. Consequently,
this document does not claim current outages, successful restores or agreement with deployed state.

## 3. What professional, DRY and SOLID mean here

### Professional and academically defensible

Every important claim needs an explicit scope, assumptions, a measurement and a counterexample that
would refute it. A passing check establishes only the property that check actually tests. “All hosts
evaluate” does not imply “all features work,” “all state is backed up,” or “a host failure is tolerated.”

Avoid universal claims such as “zero overhead,” “collision-free roaming,” “no vendor in the data path”
or “complete isolation” unless the implementation and measurements justify that scope.

### DRY

DRY concerns **knowledge**, not identical text. The same port in a service declaration and its endpoint
is duplicate knowledge when both must change together. Two similar service modules are not necessarily
one abstraction: their users, database permissions and upgrade behavior may differ.

Prefer one authoritative fact and explicit projections. Accept small local repetition when a shared
helper would hide ownership or make unrelated services change together.

### SOLID adapted to a module system

| Principle | Useful interpretation here |
|---|---|
| Single responsibility | Schema, fleet policy and backend rendering have distinct owners |
| Open/closed | Adding an ordinary service extends declarations without editing central service lists |
| Liskov substitution | A provider or host replacement preserves documented contract semantics and passes the same consumer tests |
| Interface segregation | A TCP endpoint need not inherit HTTP, dashboard, LDAP and portal behavior |
| Dependency inversion | Services describe requirements; deployment policy selects providers; adapters render backend configuration |

Nix is not an object-oriented program. Do not introduce inheritance-like helpers or generalized service
factories merely to claim SOLID compliance.

### Agnosticism

Aim for host-placement independence and explicit product adapters, not universal backend interchangeability.
An application that requires PostgreSQL should say PostgreSQL. Authentik-specific certificate names and
Caddy directives are legitimate in their adapters. They should not be mandatory vocabulary for a plain
network endpoint. Supporting only `x86_64-linux` is legitimate if stated and tested honestly.

## 4. Findings and acceptance criteria

Priority meanings: **P1** = correct before broad refactoring; **P2** = architectural/maintenance work;
**P3** = polish or conditional modernization. No P0 live incident was established.

Effort estimates are relative: **S** is a localized change; **M** crosses several modules; **L** needs
staged integration or operational verification. They are not delivery-time commitments.

### F01 — An exported deployment interface is broken

**P1 · Measured · S**

Evidence: `flake.nix:427-458`, especially line 454. The output uses `inputs.deploy-rs`, but that input
is not declared. Explicit evaluation fails even though the normal flake checks pass. Lines 445-446
also repeat the same address expression as a fallback. `roles/base.nix:45-48` repeats it again for nod.

Choose and document the supported deployment surface. The repository already presents nod as the fleet
deployment tool. If the old output is unused, prove nod's evaluated target mapping and deployment
capability before removing it; if it is supported, repair and test it. Do not add an obsolete dependency
solely to silence the error without identifying a consumer. `builtins.getEnv "DEPLOY_KEY"` also needs an
explicit impurity policy if retained: pure flake evaluation is not a reliable environment override.

**Acceptance:** every supported custom output has an explicit leaf-evaluation check; targets are non-null,
inventory-derived and use the intended fleet key. Retired interfaces have no remaining supported reader.

### F02 — Naming collision validation misses an ordinary cross-owner alias

**P1 · Measured · S**

Evidence: `contracts/naming/default.nix:59-76,178-190`. The implementation takes duplicates of aliases
that intersect canonical names. A *single* alias colliding with another endpoint's canonical name occurs
only once in that filtered list and passes. Alias-to-alias collisions outside the canonical set are
also not covered by this algorithm. An isolated two-endpoint fixture confirmed the first case.

Represent names together with their owners, then reject a name associated with more than one owner.
Define whether a redundant self-alias is allowed. Include canonical names, aliases and extra domains;
decide explicitly how node/device names share the namespace. Inspect `aliases` separately: its current
readers are naming validation/reporting, while rendering commonly uses `extraDomains`.

**Acceptance:** canonical/canonical, canonical/alias and alias/alias cross-owner collisions fail with
both owners in the error; legal self-alias handling is tested; accepted alias declarations actually reach
their intended DNS and proxy consumers.

### F03 — Network invariants verify fragments rather than effective permissions

**P1 · Measured · M**

Evidence: `checks/network-invariants.nix:89-134`. Address, port and source fragments are searched
independently over a whole rules string. They need not occur in the same rule; the check does not verify
an accepting verdict. Replacing every `accept` in the router's extra forwarding rules with `drop`
still produced zero violations. `flake.nix:275-306` permits both verdicts in its syntax-shaped check.

There is another structural blind spot: `declarationViolations` checks whether a device is carried, but
its input was already filtered to carried devices (`checks/network-invariants.nix:46-60,305-313`).

Check complete relations `(source, destination, protocol, port, interface, verdict)`. Keep an independent
packet-level test as well: checking an intermediate representation with the same projector cannot prove
the renderer correct. Validate nftables syntax in a suitable namespace/VM and exercise selected allow
and deny paths, including IPv6 where supported.

**Acceptance:** changing an allow to a deny, swapping ports between devices, broadening a source set,
adding an unintended broad accept and dropping a required rule each fail an appropriate check. A
non-carried declared device is checked before filtering it out. Assertions name their exact scope.

### F04 — Backup hooks are an unexercised, broken API

**P1 · Measured and source-confirmed · M**

Evidence: `contracts/backup/default.nix:33-43,79-89,105-113`. A non-null `preDumpHook` generates
`services.restic.backups.daily.backupPreparePrune`, which the pinned NixOS module does not provide.
The evaluation error recommends `backupPrepareCommand` or `backupCleanupCommand` instead.

Further problems:

- `postDumpHook` has no reader.
- `storage.preBackupHook` is a separate, unread declaration (`contracts/storage/default.nix:31-35`).
- Pre-dump hook collection does not filter `backup.enable`.
- The composite shell script has no explicit failure propagation between hooks.
- A `types.package` value need not itself be an executable file; interpolation alone does not define
  how to run a package with a binary under `bin/`.

Define one lifecycle API, including command resolution, ordering, failure handling and cleanup semantics.
Connect it to the actual pinned NixOS options. Remove the competing spelling after checking consumers.

**Acceptance:** a fixture runs a real dump before backup; a failing first hook prevents a successful
backup signal; disabled contracts run no hooks; cleanup behavior is verified on both success and failure.

### F05 — Backup coverage is implicit, and restore correctness is not established

**P1 · Measured and source-confirmed · L**

Evidence: `features/system/backups/restic/default.nix:16-32,43-60`,
`contracts/backup/default.nix:47-76`, `features/services/postgresql/default.nix:29-35`, and evaluated paths.

Contract paths merge with broad `/var/lib` paths. On `hom-srv-01`, `/data/storage/docs` occurs twice;
movie, TV and download directories are included through contracts. This is not proof of duplicated bytes
in Restic, but it obscures policy and can make expensive, replaceable data part of the backup scope.
The broad fallback also masks missing service declarations.

`cld-ops-01` has Restic disabled while Open WebUI declares persistent state
(`features/services/open-webui/default.nix:226-228`). That is a confirmed gap in this repository's
Restic coverage, not proof that no external backup exists. *(Resolved by decision D13 in §10: the ops
host is intentionally without Restic and that is declared, not left as an omission.)* A PostgreSQL dump
scheduled an hour before Restic is a scheduling convention, not a dependency or freshness guarantee.
Copying the live database directory does not replace a database-consistent recovery method.

Inventory durable service state, owner, criticality, backup disposition and restore procedure. Distinguish
irrecoverable data from regenerable caches/media. Define RPO and RTO for relevant service classes, plus
the treatment of intentionally unprotected state. Keep UI-owned state legitimate when it is recoverable.

**Acceptance:** every stateful service has an explicit backup or exclusion decision; database backups
have verified freshness and consistency; an isolated restore starts the application and validates useful
data. The previous backup coverage is retained until replacement recovery is demonstrated.

### F06 — Monitoring defaults generate invalid probes and ignore declared health paths

**P1 · Measured · M**

Evidence: `contracts/endpoints/default.nix:372-425,524-529` and
`features/services/monitoring/prometheus/default.nix:84-102`. HTTP monitoring defaults to true for every
endpoint, and `localUrl` always uses HTTP. The actual projection includes:

| Endpoint | Generated local HTTP target | Problem |
|---|---|---|
| SSH | `http://127.0.0.1:22/` | SSH is not HTTP |
| WireGuard transport | `http://127.0.0.1:51820/` | WireGuard is UDP, not HTTP |
| CouchDB EPMD | `http://127.0.0.1:4369/` | Erlang port mapper is not HTTP |
| Authentik HTTPS endpoint | `http://127.0.0.1:9443/` | HTTP scheme on an HTTPS endpoint |
| Sonarr | `http://127.0.0.1:8989/` | Declared `healthProbePath = "/ping"` is not consumed |

`healthProbePath` is written by several applications but has no executing reader. Monitoring reads the
separate `monitoring.http.path`. These are rendered-configuration defects; live alert state was not read.

Model application protocol independently from transport. Make probe selection explicit or safely
derived; a UDP service should not silently inherit an HTTP or TCP test. Have one health-path declaration
and explicitly distinguish service health, authentication redirects and end-user availability.

**Acceptance:** non-HTTP endpoints generate no HTTP targets; HTTPS uses the correct scheme; changing a
service's health path changes its rendered probe; each probe's expected status and authentication behavior
are documented and verified against the service.

### F07 — Several contracts are schemas without implemented semantics

**P2 · Source-confirmed · M**

Evidence: `contracts/telemetry/default.nix`, `contracts/dependencies/default.nix:33-55,124-159`,
`features/services/redis/default.nix` and F04/F06.

The telemetry fields for metrics, logs and alerts have no projection reader in the reviewed tree.
Prometheus uses endpoint `monitoring` instead. PostgreSQL `extensions` is declared but omitted from the
dependency projection. Redis consumers and `dbIndex` are declared, while the Redis feature creates a
fixed `system` instance without reading them.

Create a field-to-consumer table for public custom options. For each field, either implement a needed
behavior, explicitly reject unsupported use, or remove the unused API after reader verification. Do not
implement imaginary features just to justify a schema. Check ordinary NixOS module facilities first.

**Acceptance:** a supported field has an identified consumer and a behavioral example; non-default use
cannot silently do nothing. There is one authoritative model for each monitoring and backup fact.

**Decision D14:** retain and implement telemetry as the observability contract. Move the existing
endpoint-monitoring declarations and their consumers to it using validated endpoint references;
the absence of a reader is an implementation gap, not evidence that this domain should be deleted.

### F08 — Database consumers bypass the contract and receive superuser privileges

**P1 · Source-confirmed · M**

Evidence: `features/services/sonarr/default.nix:45-71` and
`features/services/radarr/default.nix:45-71`. Both declare PostgreSQL users/databases directly and set
`ensureClauses.superuser = true`. This undermines the consumer/provider boundary and gives each
application authority beyond its own databases.

Model multi-database ownership/grants in the provider adapter where genuinely needed. Determine the
applications' migration requirements before narrowing privileges; do not blindly remove a working grant.
The same service module should not separately own database names in client settings and provisioning.

**Acceptance:** applications can initialize, migrate and operate with the documented minimum grants;
their roles cannot access unrelated application data; client and provisioned database identities derive
from one declaration. Old privileges are removed only after this is proven.

### F09 — Secret decryption scope is broader than the documentation says

**P1 · Source-confirmed · L**

Evidence: `.sops.yaml:37-47`, recipient metadata in `secrets/secrets.yaml`, and
`features/system/common/default.nix:97-100`. The shared file is encrypted to the operator, all five hosts
and CI. A recipient of that file can decrypt the file's contents, not merely the keys its local
`sops.secrets` declarations install. This contradicts the narrower reading of
`docs/security.md:54-64`. Separate deploy-key and tunnel files already exist, contrary to the repeated
“one file” description.

Define secret groups by actual decryption audience. Partition files only where that creates a meaningful
boundary, retain operator recovery, and state CI's needs explicitly. Remember that removing a recipient
does not revoke values it previously learned: rotation and credential revocation are separate operations.

**Acceptance:** a disposable recipient-matrix test establishes which identities can decrypt which
fixture files; all hosts still activate with the intended secrets; docs distinguish decryption authority,
installed secret paths and runtime file ownership. No production secret needs to appear in test output.

### F10 — CI and the local hook do not cover the promised change surface

**P1 · Source-confirmed · S/M**

Evidence: `.github/workflows/ci.yml:3-8`, `.githooks/pre-commit:4-18`, `flake.nix:223-400`.

- CI path filters omit `checks/**`; a change confined to the checks does not trigger this workflow.
- Secret/SOPS configuration and hook changes are also omitted.
- No formatting check is included in the flake checks. The hook formats, but hooks are optional.
- The hook formats working-tree files and then `git add`s them. A partially staged file can therefore
  pull unrelated unstaged changes into a commit.
- Newline-separated names plus `xargs` are not safe for all valid filenames.
- `AGENTS.md`'s “pre-commit runs the three above” is ambiguous: the hook runs `nix fmt`, `deadnix` and
  `statix`, not `nix flake check`, so the wording should name the three explicitly rather than invite a
  reader to believe evaluation is covered.

Prefer a trigger policy that cannot accidentally omit evaluable source. Make formatting check-only in CI.
Either make the hook index-aware or have it report formatting changes for the user to stage explicitly.
Keep its speed/coverage promise honest rather than hiding expensive evaluation in every commit.

**Acceptance:** check-only, SOPS-policy-only and hook-only changes get their intended validation;
formatting drift fails CI; a partially staged file retains its unstaged hunk after the hook.

### F11 — Topology schema, site inventory and policy are one module

**P2 · Source-confirmed / design recommendation · M**

Evidence: `features/system/networking/topology/default.nix`, 616 lines. It contains option types,
site domains, host/device inventory, trust vocabulary, default subnets and derived policy.

Separate the site facts from the reusable schema and pure projections. Keep a single authoritative
inventory, explicitly imported by composition. The current use of `mkDefault` around whole maps also
needs a documented extension policy: adding an ordinary-priority map definition can replace the
default-priority map rather than simply extending one entry.

**Acceptance:** a second synthetic inventory evaluates without editing schema/projection source; adding
a host does not accidentally discard other hosts; evaluated production names, addresses and policies
remain equivalent during the extraction.

### F12 — Zone names are coupled to trust-level names

**P2 · Source-confirmed · M**

Evidence: topology lines 16-23, 55-60, 136-141 and 281-285. The comments correctly distinguish zones from
trust levels, but host and device `zone` options use the trust-level enum. A new zone such as `lab` with
`trustLevel = "corp"` can be declared in `subnets` yet cannot be selected as a host zone.

Use zone references with existence assertions, separate from policy categories. Inventory validation
should consistently cover address syntax, subnet membership, uniqueness and references. Existing
gateway assertions are useful but are not a substitute for a coherent inventory validation boundary.
If `/24` is an intentional limitation, state and enforce it rather than implying arbitrary CIDR support.

**Acceptance:** two zones can share a trust level; unknown zones fail clearly; invalid/duplicate addresses
and conflicting identities are rejected before rendering. No claimed formal security lattice is inferred
merely from the order of an enum.

### F13 — Provider selection and deployment targets still encode host placement

**P2 · Source-confirmed · M**

Evidence:

- `flake.nix:187-190,460-509`: fixed configuration hosts and repeated router/AP addresses.
- `features/services/authentik/outpost/proxy/default.nix:22-35`: fixed edge host, port and domain.
- `hosts/hom-srv-01/configuration.nix:46-49`: manually constructed Authentik core URL.
- Monitoring pipeline and CrowdSec defaults both name `cld-edge-01`.

Make provider binding an explicit deployment-policy fact, or derive a unique provider with an assertion
when uniqueness is the real contract. Use provider endpoint declarations for the address, port and URL.
Do not conflate ingress host, identity host, monitoring host and reconciler executor just because they
currently coincide.

**Acceptance:** moving a provider between suitable fixture hosts changes only placement/binding; its
consumers follow without source edits. Agentless addresses match inventory. Missing/ambiguous providers
produce diagnostics rather than a loopback fallback or an alphabetical choice.

### F14 — Fleet traversal is repeated, and standalone fallbacks have the wrong shape

**P2 · Source-confirmed · M**

Evidence: `contracts/naming/default.nix:27-49`, Caddy lines 25-56, Prometheus lines 40-63, and analogous
DNS, CrowdSec and blueprint collectors. Multiple consumers independently flatten all host contracts.
Several fallbacks construct `{ host = config; }`, but the downstream reader expects `hostConfig.config`.
For example, Prometheus reads `hostCfg.config.my...` after storing `config` directly in the fallback.
Optional `or { }` can then hide the mismatch by producing an empty projection.

Introduce a narrow, read-only fleet view of the declarations consumers need. Preserve laziness and avoid
passing full system outputs into a new eager normalization step: the current cross-host references can
be sensitive to evaluation recursion. Make standalone mode either genuinely supported with the same
shape or explicitly unsupported.

**Acceptance:** local-only fixtures include their local services; fleet and standalone shapes agree;
projection output stays equivalent; evaluation time/memory is measured before and after, not assumed to
improve just because code was deduplicated.

### F15 — The endpoint contract has too many independent responsibilities

**P2 · Design recommendation grounded in source · M**

Evidence: `contracts/endpoints/default.nix`, 980 lines. It combines transport, HTTP ingress, Authentik
OIDC, LDAP, firewall rules, UI metadata, portal readouts/actions, locale validation and derived consumers.
The consequences are visible in F06 and F07; line count itself is not the defect.

Separate cohesive contracts/adapters: transport/endpoints, HTTP ingress, identity integration,
observability and portal presentation. Retain the service's cohesive declaration site; splitting
implementation must not require six files to add a simple application. Keep Caddy raw directives and
Authentik signing-key names behind clearly marked backend-specific extension points.

**Acceptance:** a raw TCP service needs only transport and its chosen checks; portal changes do not alter
firewall semantics; existing service declarations migrate without silently changing emitted artifacts.

**Decision D14:** endpoints own interface facts; telemetry owns observation policy, identity owns
OIDC/LDAP integration, and portal owns presentation and actions. These remain cohesive declarations
under `my.contracts.provides.<service>`, with schemas separated by domain and backend projections
owned by their implementing features. See §10.5 for the agreed boundaries and verification.

### F16 — Configurable interface names are only partially respected

**P2 · Source-confirmed · S/M**

Evidence: `features/system/networking/wireguard/default.nix:189-192,292`, versus hard-coded `wg0` in
`contracts/endpoints/default.nix:743-761`, `checks/network-invariants.nix:128-145` and
`lib/audit/default.nix:107-111`.

Either make `wg0` an explicit invariant and remove the misleading customization, or project the selected
interface name into all consumers. Apply the same rule to redundant protocol fields: endpoint
`protocol` and `directAccess.protocol` should have a documented derivation or explicit override meaning.

**Acceptance:** a fixture using another interface name has matching service rules, routing and checks,
or evaluation rejects the unsupported name immediately. UDP declarations cannot silently open TCP only.

### F17 — List order makes identity and provider decisions

**P2 · Source-confirmed · M**

Evidence: `lib/core/system-builder.nix:39-54`, `features/system/user/default.nix:26-34`,
`contracts/endpoints/default.nix:795-818`, and WireGuard lines 34-41.

Alphabetical discovery chooses a primary user; the first LDAP-enabled endpoint determines a whole
service's LDAP consumer; a missing configured relay falls back to the first relay. These are semantic
decisions disguised as traversal order. Using `head` is fine when uniqueness/non-emptiness is asserted;
it is not fine when it silently resolves an ambiguous policy.

Declare identity and provider choices explicitly, or assert exactly one valid candidate. For multiple
LDAP endpoints, require equal policies or model separate consumers. Provider selection during evaluation
must not be described as live failover.

**Acceptance:** adding an alphabetically earlier user/endpoint/relay does not alter unrelated policy;
ambiguous selections fail with actionable messages.

### F18 — User discovery is duplicated and exposes an ineffective option

**P2 · Source-confirmed · M**

Evidence: `features/system/user/default.nix:10-24,38-42`, `lib/core/system-builder.nix:39-70`,
`user/philipp/home.nix:16-18`. `my.user.usersDir` is declared, but discovery reads the hard-coded path.
System and Home Manager users are discovered separately. The user-specific Home Manager file also
derives its username from the global primary user rather than necessarily its own identity.

Choose explicit fleet user assignments and one metadata/discovery source. Keep personal preferences in
the user's configuration. A new directory should not silently install a new account and home profile
everywhere unless that is the documented policy.

**Acceptance:** two-user fixtures have correct distinct usernames, homes and roles; changing a supported
metadata path actually changes discovery; missing home files and unsupported assignments do not silently
drop requested configuration.

### F19 — Runtime audits are useful samples, not complete exposure proofs

**P2 · Source-confirmed · M**

Evidence: `lib/audit/default.nix:19-32,81-118,129-157`. The network sample names Jellyfin and the first
device. The exposure projection flattens endpoint policy into port lists; that loses the distinction
between permitted source/interface scopes. It cannot alone prove that a listener is reachable only by
the right callers. The code comments already distinguish some hub-denied probes from allowed client paths.

Keep explicit representative probes when sampling is intended, but describe their coverage honestly.
For scope verification, test a caller/destination/protocol matrix across the relevant host classes and
include both expected success and expected denial. Check all configured resolvers where equivalence is
claimed, instead of accepting one as representative without an equality check.

**Acceptance:** reports identify sample coverage; a port moved from mesh-only to public exposure is
detected by an appropriate check; a denied-source success and an allowed-source failure are both visible.

### F20 — Documentation overstates formal properties and contains contradictory history

**P1 for security/availability claims; otherwise P2 · Source-confirmed · M**

Concrete examples:

| Claim/location | Problem |
|---|---|
| `docs/architecture.md:17-18` | RFC1918 addressing cannot guarantee no collision with a visited network |
| Architecture lines 127-129 | Two WireGuard peers do not establish automatic transit failover; the primary carries broad prefixes, the secondary only its own addresses |
| Architecture lines 348-350 | Loading a disabled module does not exercise every lazy branch; F04 is a direct counterexample |
| Architecture lines 196-199 | A DNS-plane table still names Blocky while the active implementation uses Knot Resolver |
| Architecture lines 316-320 | Scope names and backup/telemetry capabilities do not fully match the schemas and consumers |
| `docs/security.md:12-35` | Flat-L2 category-based firewall rules do not enforce Bell-LaPadula read/write information-flow properties or complete LAN isolation |
| Security lines 133-134 | “Every host-to-host path is the mesh” contradicts `lib/addresses.nix`, which intentionally prefers LAN addresses for local peers |
| Security lines 137-139 | “Ingress is the only public surface” omits the documented public SSH and other explicitly exposed transports |
| Security lines 122-125 | Counting hardening declarations in local wrappers ignores hardening inherited from upstream NixOS modules |
| `docs/practices.md:3-5,186-247` | A self-described shrinking gap list and historical blocker narrative contradict the present-specification policy |

Use precise terms: trust categories, source allow-lists, flat-L2 limitations, explicit application
authentication and declared admin authority. WireGuard public keys use Curve25519 key agreement, not
Ed25519 as the topology option description currently says. Formal terminology should identify an actual
formal model and enforcement mechanism, not lend authority to an unrelated implementation.

**Acceptance:** present-state specifications have no unresolved historical status sections; each strong
security/availability claim points to a scoped assertion or repeatable measurement; operational lessons
are distilled into rules, with incident detail retained in history/issues.

### F21 — The check matrix covers current hosts, not the supported configuration space

**P2 · Measured and source-confirmed · M/L**

Evidence: host evaluation in `flake.nix:239-247`, the discovered-feature loader and the successful
baseline contrasted with F04. Auto-importing modules is useful but does not instantiate unused feature
branches or option combinations. A disabled rollback module is also not proven working merely by being
present in Git; see Blocky in `hosts/hom-srv-01/configuration.nix:34-36`.

Add a small supported-mode fixture matrix, selected by actual promises rather than a Cartesian product:
disabled/enabled contracts, non-default interface, two users, a second zone of the same trust level,
provider absent/unique/ambiguous and hooks enabled. Add negative fixtures for the high-risk invariants.
Use selected NixOS VM tests for effects that evaluation cannot prove, especially packet policy and
backup lifecycle. The existing updater's failure/rollback tests are a good example of useful negative tests.

**Acceptance:** supported non-default branches are exercised; disabling a feature removes its intended
services/secrets/rules; intentionally breaking a critical invariant fails the test that claims to cover it.
Keep inactive code only with a supported use case or a verified rollback purpose.

### F22 — The flake entry point mixes assembly with implementation

**P2 · Design recommendation · M**

Evidence: `flake.nix`, 511 lines. Inline package workaround code, check programs, app wrappers,
deployment compatibility and target definitions share the composition entry point.

Extract only cohesive units: check definitions to `checks/`, app composition to a small builder, and
package fixes to their existing overlay area. Bind the audit import once rather than repeating it for
two apps. Do not replace familiar Nix with a new framework unless a concrete remaining problem requires it.

**Acceptance:** the entry point explains inputs, systems and composition; existing output names and
derivation behavior are preserved by leaf/output comparisons. File count or a line limit is not the goal.

### F23 — Modernization needs a bounded support and dependency policy

**P3, with individual dependency risks assessed separately · Source-confirmed / design recommendation · M**

Evidence: single `system = "x86_64-linux"` in `flake.nix:78`, shared `pkgs`, the “multi-architecture”
system-builder header, inline package workaround, `permittedInsecurePackages`, and package overlays.

The lockfile already pins moving input branches. Using unstable inputs is not itself non-reproducible.
The useful improvements are:

- State the supported platform. Add per-system/per-host package sets only when another architecture
  is actually needed; merely expanding output names does not prove package or hardware support.
- Give each overlay workaround an upstream reference, reason, affected version range and removal check.
  A disabled upstream test, such as Paperless's `test_search_more_like`, is a maintenance obligation.
- Review insecure-package exceptions against actual consumers and current upstream fixes. Do not remove
  the pnpm exception without proving the replacement builds the dependent packages.
- Preserve the update workflow's existing validation before push. Consider reviewed update batches and
  artifact provenance when operationally useful; direct push is a policy decision, not automatically a bug.
- Decide whether CI deliberately requires the private Attic cache. Setup currently fails before builds
  if its cache probe fails, which makes cache availability a prerequisite for validation.
- Explain the supported Nix/Lix toolchain boundary: hosts select Lix, while CI uses its installer action.

**Acceptance:** support claims match tested systems; every temporary override has a removal condition;
updates preserve a recorded tested revision and dependency hashes; cache-outage behavior is deliberate.

### F24 — Small consistency defects are cheap to fix after semantic issues

**P3 · Source-confirmed · S**

Examples: German implementation comments in the flake/topology/database module despite the English
policy; stale Tailscale wording in the proxy outpost; unused compatibility shim `lib/helper.nix` with
no repository reader found; deprecated `libreoffice-fresh` in
`user/philipp/profiles/graphical.nix:20`; copied historical narratives in comments.

Locale-specific UI text, such as `dashboard.description.de`, is intentional and should remain localized.
Do not apply a blanket “remove German strings” transformation. Do not remove an unused-looking external
API or rollback component until supported consumers have been checked.

There is also a specific consistency issue in portal validation:
`contracts/endpoints/default.nix:831-834,875-881` hard-codes `de`/`en`, while dashboard descriptions use
`my.portal.locales`. A third locale is therefore data for only part of the schema.

**Acceptance:** prose follows its declared language; deprecation warnings are resolved; locale fixtures
cover all text-bearing fields; removed compatibility code has no supported consumer.

### F25 — Recursive `default.nix` discovery confuses module boundaries with file layout

**P2 · Measured · M**

Evidence: `lib/core/module-loader.nix:6-14`. The scanner visits every directory below a root and includes
every entry named `default.nix`. It does not distinguish a feature module, a helper library, a fixture,
a package expression or a directory-level aggregator. It also continues below a discovered module.

An isolated tree confirmed discovery of `service/lib/default.nix`, `service/tests/default.nix` and
`.hidden/default.nix`, alongside the intended parent and child modules. The production tree currently
avoids the helper collision by naming helpers `blueprint.nix`, `blueprints.nix`, `switches.nix` and
`sonoff-basic.nix`; that convention is implicit rather than enforced. A reasonable helper extraction to
`lib/default.nix` would therefore change the system's import graph.

Reserve a distinctive, context-specific module entry filename, such as `nixos.nix`, for automatic
discovery under `features/`. Give private helpers/tests/templates explicit non-discovered boundaries.
Alternatively, an explicit module registry is valid, but do not maintain it in parallel with an
independent scanner and let them disagree. Recommended concrete rules are in section 9.

**Acceptance:** adding a helper, fixture or asset changes no module imports; adding a feature entrypoint
adds exactly that intended module; nested independent features remain supported. A move of implementation
files alone must not enable, disable or replace another module.

### F26 — File-kind, hidden-directory and symlink behavior is accidental

**P2 · Measured · S**

Evidence: `lib/core/module-loader.nix:9-12`. `hasAttr "default.nix" entries` checks only the name, not
whether it is a regular file. Recursion accepts directories only, which treats symlinks differently
depending on their position.

The fixture produced these concrete results:

| Fixture entry | Current behavior |
|---|---|
| Directory literally named `default.nix` | Included as though it were a module entrypoint |
| Symlink named `default.nix` | Included |
| Symlink to a directory containing a module | Not traversed |
| Hidden directory containing `default.nix` | Traversed and included |
| Ordinary `ordinary.nix` | Not included |

Adopt a documented regular-file entrypoint rule and explicit handling for disallowed entry kinds. Reject
malformed entrypoints with their path; do not turn them into obscure import failures later. Skip hidden
and designated private directories deliberately. Avoid following directory symlinks unless cycle and
source-boundary behavior is actually needed and specified.

The current traversal is deterministic: `attrNames` orders sibling directories lexicographically and
parents are included before descendants. Preserve that behavior unless changing it intentionally;
module-list order can affect equal-priority list merging. Priority must still be expressed through
`mkDefault`, `mkForce`, `mkBefore` and `mkAfter`, not a folder prefixed with `00-`.

**Acceptance:** fixtures cover each file kind and traversal decision, with stable ordering and clear
errors. Tests operate on the source visible to Nix; a Git-backed flake does not automatically include
every untracked scratch file in the working directory.

### F27 — `mkSystem` is a repository-bound composition function, not a generic builder

**P2 · Source-confirmed and measured · M**

Evidence: `lib/core/system-builder.nix:24-28,39-70,79-97`. It hard-codes the feature, contract, host and
user roots, discovers users, chooses defaults, installs Home Manager and constructs the complete system.
It also binds its library dependency to `inputs.nixpkgs-unstable` and accepts a separate
`home-manager-unstable` dependency through its enclosing function.

There is no explicit “no Home Manager users” value: `users = []` means “discover all users.” A builder
fixture with a stubbed `nixosSystem` confirmed that an explicitly empty list produces `philipp`.
Missing home files are silently filtered out. Optional absence of `contracts/` is also hidden even though
the rest of this repository depends heavily on the contracts.

Separate three small responsibilities: source discovery, repository composition and the call to
`nixosSystem`. Pass discovered module paths and explicit user assignments into composition. Only add
parameters that have an actual reader/use case; a dozen configurable path suffixes would be worse than
the current short function. `[]` should mean none; use an explicit discovery step or a distinct default
value when discovery is desired. Assert required roots and selected home entries exist.

**Acceptance:** an isolated fixture can compose a host without assuming this checkout's layout; an empty
user set stays empty; selected missing/duplicate users fail clearly; platform and package-set agreement
is validated. Existing production module and home assignments remain equivalent during extraction.

### F28 — Registration, system activation and per-user activation are not consistently separated

**P1 for ineffective disable behavior; P2 for structure · Measured and source-confirmed · M**

Evidence: `features/dev/git/default.nix:23-60,64-140`,
`features/desktop/webapps/default.nix:70-85,170-194`, and system-builder Home Manager wiring.

Registering Home Manager options unconditionally can be correct: their schemas must exist before users
can enable them. But the Git feature's system `enable` is declared and never used to gate its secret
effects. Forcing `my.features.dev.git.enable = false` on `hom-wrk-01` still leaves both the GitHub PAT
secret and its template declared. The WebApps system flag is likewise not the controlling predicate of
the Home Manager package effect, which uses its own user flag and the host role.

Move pure Home Manager implementation into an explicit `home.nix` companion where that improves
readability; let the NixOS entrypoint own system integration and schema registration. Define the two
activation levels deliberately. Keep system-owned secrets gated by the supported system/consumer policy.
Move personal Git defaults out of the reusable implementation. The “zero hardcoded usernames” comment
in the Git module does not match its current defaults.

**Acceptance:** a disabled system feature has no unintended system effects; user activation affects only
the selected user; registration alone creates no accounts or credentials. Standalone Home Manager
support is tested before advertised, not inferred from an `osConfig ? { }` argument.

### F29 — Directory categories mix scope, application purpose and implementation role

**P2 · Source-confirmed / design recommendation · M**

The top-level distinction between `hosts/`, `roles/`, `features/`, `contracts/` and `packages/` is useful
and should remain. The weaker boundaries are inside those areas:

- `features/system/networking/topology` is always-loaded schema, policy and inventory, not an optional
  network implementation.
- `features/system/user` is another always-active policy module without a feature enable option.
- `features/system/common/geoip` is an independently enabled service placed under a vague common bucket.
- `features/dev/containers` configures the Docker daemon, including on a server; its location suggests
  a workstation-only concern it does not enforce.
- `lib/audit` builds operational executables, and `lib/updaters` contains an application and tests;
  neither is simply a pure Nix utility library.
- `media/` holds visual assets, while `features/media/` holds application capabilities. The repeated
  word refers to two different concepts.

Prefer a clear placement decision table over moving every feature to a new taxonomy. Extract inventory
and baseline policy, place operational programs with their app builders, and consider `assets/` for the
image collection. Keep helpers at the narrowest shared domain owner, including a feature area's own
`lib/`. Multiple feature consumers do not by themselves justify promotion into the root `lib/`, which
should contain genuinely cross-domain composition and module infrastructure.

**Acceptance:** contributors can determine a new file's owner and import context from the convention;
there is no miscellaneous growth into `common`, `core` or `helper`; physical moves are behavior-preserving.

### F30 — File names, option identities and external service names need distinct rules

**P2 · Source-confirmed / design recommendation · M**

Evidence: host discovery in `flake.nix:138-142`, `lib/core/system-builder.nix:87`, metadata discovery,
`lib/endpoints.nix:15-16`, and feature naming throughout the tree.

Several current distinctions are justified and should not be “cleaned up” blindly: a generated
`hardware-configuration.nix` differs from hand-maintained `hardware-specific.nix`; an Attic client is
not its server; a deployment host ID is not a service DNS name. Other distinctions lack a clear contract:

- `hostname` is passed by the builder while each host repeats `networking.hostName`.
- A user directory supplies identity while `metadata.nix` also carries `username`.
- `vyrx-landing` now owns portal behavior, but the historical name remains in options and inputs.
- `dns` describes a capability while `blocky`, `caddy` and `postgresql` name products. Both naming styles
  are valid, but their promised abstraction levels should be stated.
- Endpoint keys `default` and `web` both normalize to the service ID. Other service/endpoint splits
  can also normalize to the same hyphenated identifier. That requires uniqueness checks wherever those
  IDs become application slugs, dashboard keys or monitoring labels.

Choose one authoritative host/user ID and derive or assert the other representations. Rename internal
paths separately from public option APIs, secret keys, database names and endpoint identities. An option
rename may need a temporary NixOS alias and warning; a persisted identity rename needs a real migration,
not a search-and-replace. Do not rename a module to its current DNS label.

**Acceptance:** directory moves preserve public identities; redundant host/user identity values agree;
normalized service IDs are unique for their consumer; future names follow the table in section 9.

### F31 — Library interfaces do not clearly advertise purity and dependencies

**P2 · Source-confirmed · S/M**

Evidence: `lib/default.nix`, `lib/helper.nix`, `lib/addresses.nix:17`, `lib/endpoints.nix:7`,
`lib/features.nix:12-46`, and `lib/core/system-builder.nix`.

The nominal library entrypoint requires Home Manager and exports only `mkSystem`; independent helpers
are imported by path. Address and endpoint helpers accept an ignored argument, while their consumers
often pass `{ inherit lib; }`, suggesting a dependency that does not exist. `helper.nix` adds another
entrypoint solely as compatibility forwarding.

Separate pure domain helpers from NixOS composition and executable builders. Use an attrset export for
a dependency-free utility; use `{ lib }:` when `lib` is required. Keep the standard NixOS module argument
convention for modules rather than mixing those interfaces. A reusable `myLib` can expose cohesive,
small namespaces without shadowing nixpkgs `lib` or eagerly importing unrelated subsystems.

The dependency helper can use standard `lib.setAttrByPath` instead of its own `mkNested`; first retain
its actual semantics: `mkDefault` enablement plus a loud assertion on an explicitly disabled dependency.
Validate empty/unknown dotted references and include the requesting feature in errors. This is a useful
small helper, not a reason to introduce a dependency resolver parallel to the NixOS module system.

**Acceptance:** helper signatures list actual dependencies; pure helpers work without Home Manager or a
flake; dependency failures identify both requester and dependency; no ineffective compatibility layer
remains after its consumers have moved.

### F32 — Eagerly importing module values weakens path-based identity and diagnostics

**P2 · Source-confirmed, with a measured deduplication control · S**

Evidence: `lib/core/system-builder.nix:66` uses `imports = [ (import homeFile) ]` instead of passing
`homeFile`. NixOS/Home Manager can import module paths themselves and retain meaningful source identity
for diagnostics, deduplication and path-based disabling. An already imported function no longer carries
the same path identity unless it is supplied explicitly.

Prefer paths in `imports` for ordinary modules. Import functions directly only when genuinely constructing
a parameterized module/factory, and preserve source location where appropriate.

Importantly, the current feature scanner's parent-plus-child behavior is **not inherently a duplicate
activation bug**. A control fixture where the parent explicitly imports a child and discovery includes
the same child path produced each module's list contribution once. Nix's module machinery already
deduplicates those paths. Preserve and use that behavior instead of adding a custom evaluator or claiming
every repeated path doubles configuration.

**Acceptance:** error messages identify the real source file; ordinary repeated path imports retain
standard module identity; meaningful `disabledModules` use is not defeated by unnecessary pre-imports.

### F33 — Discovery can be shared, but it is not the measured evaluation bottleneck

**P2 for explicit composition; P3 for scanner micro-optimization · Measured · S/M**

The actual scanner selects **82 feature modules and 7 contract modules**, visiting **110 feature
directories and 8 contract directories**. Discovery is inside `mkSystem`, so the same tree traversal
expression is constructed per host. Nix may share/cache parts of evaluation and filesystem access;
this is not evidence of five independent disk reads for every file.

An isolated, output-equivalent benchmark compared five per-host discoveries with one shared discovery
list passed to five consumers. Six measured samples followed a warm-up pair, alternating case order:

| Scope | Median wall time | Range |
|---|---:|---:|
| Per-host discovery model | 24.01 ms | 23.40-26.36 ms |
| Shared discovery model | 18.75 ms | 18.02-19.77 ms |
| Actual five-host `system.build.toplevel.drvPath` evaluation | 39.56 s | 38.61-39.64 s, three samples |

The isolated difference is about **5.25 ms**, not a demonstrated multi-second fleet improvement.
Representative scanner statistics reported 5,849 versus 1,185 function calls and 722,032 versus 206,192
GC-allocated bytes. The last fleet run reported about 8.20 billion allocated bytes and a 4.98-billion-byte
GC heap. These are evaluator statistics, **not peak RSS or retained configuration size**.

Share a discovered path list at the composition boundary because ownership and dependencies become
clearer. For meaningful performance work, profile module/package evaluation, repeated fleet projections
and cross-host forcing next. Do not conditionally import features based on their own `config.enable`:
that risks module-graph recursion and missing options. Do not replace path imports with `readFile` plus
custom evaluation. The scanner is already simple and uses deterministic traversal with `concatMap`.

**Acceptance:** shared and original discovery output match; generated host outputs preserve intended
behavior; an end-to-end before/after measurement demonstrates any claimed fleet speedup. No performance
claim is based only on module count or the isolated microbenchmark.

### F34 — Organization conventions need a small executable structural check

**P2 · Design recommendation grounded in measured fixtures · M**

The repository has linting for Nix expressions but no dedicated gate for its discovery contract. A file
can be formatted, statically clean and still be discovered as the wrong kind of module. The organization
rules should be tested without constructing the entire five-host fleet.

Add `checks/module-discovery.nix` or an equivalent focused test with isolated fixture trees. Check the
entrypoint convention, exclusions, file kinds, ordering, expected scopes and supported nested modules.
Derive a human-readable module inventory from that same result rather than maintaining a separate list.
Check host/user references at their composition boundary. A schema/option check should establish actual
feature metadata rather than grepping code for `enable` and assuming that proves gating.

**Acceptance:** each malformed fixture fails for the intended reason; expected valid nested imports work;
helper-only additions leave discovery unchanged; a scope mismatch is diagnosed before an expensive fleet
build. Integrate the check into the corrected CI trigger surface from F10.

### F35 — Network helpers belong to their domain; separate policy from nftables rendering

**P2 · Source-confirmed / design recommendation · S/M**

Evidence: `lib/nftables.nix:16-41`, its imports in `contracts/endpoints/default.nix`,
`features/system/networking/wireguard/default.nix` and `checks/network-invariants.nix`, and the separate
configuration module `features/system/networking/firewall/default.nix:24-42`.

The name of a technology does not determine whether a file belongs in `lib/`. This file takes explicit
inputs and returns an attrset of functions. It declares no NixOS options, enables no service, installs
no firewall and runs no command. It is a library implementation, but that does not establish the root
`lib/` as its best owner. The network area is the narrower shared owner for its rendering consumers.
Use that area's existing local-library pattern rather than expanding a global collection of domain
helpers. Moving the entire file without separating source policy from rendering would retain its mixed
responsibilities.

The actual boundary problem is visible at function level:

| Function | Responsibility | Confirmed production/check consumers |
|---|---|---|
| `addressSet` | Spell a set of addresses in nftables syntax | Endpoint input rules and WireGuard device-forwarding rules |
| `rule` | Join rule fragments into nftables text | Endpoint input rules and WireGuard device-forwarding rules |
| `portSet` | Spell a port set in nftables syntax | No reference found in the repository search; verify supported external consumers before removing |
| `sourcesOfTrust` | Select addresses from topology trust categories | Both rule generators and the network invariant check |

`sourcesOfTrust` has no nftables-specific operation. Its current location forces a policy check to
import a backend-named renderer simply to select source addresses. Conversely, `rule` is a string
formatter, not a parser or a proof that the rule is correct; the file header's statement that syntax
errors cannot reach a running host overstates the validation described in F03.

**Recommended split:**

- `contracts/topology/lib/access-sources.nix`: backend-independent source selection owned by the
  topology/access model, alongside the proposed topology contract extraction from F11/F12. Keep
  `sourcesOfTrust` initially to avoid mixing API renaming into a physical extraction.
- `features/system/networking/lib/nftables-render.nix`: shared rendering implementation owned by the
  network area, with actual guarantees stated narrowly. Remove `portSet` only after checking its
  supported-reader boundary.
- Keep NixOS firewall enablement/default policy in the firewall feature. Moving pure helpers does not
  justify duplicating or scattering those system settings.

Network-owned endpoint and WireGuard adapters may import both helpers. Endpoint contracts should declare
desired reachability; the network area should translate it into firewall rules. Move the current nftables
projection out of `contracts/endpoints/default.nix` as part of the coordinated F15 refactor, so the
contract does not depend on feature implementation. A policy-only check should import only
`access-sources.nix`; a test of emitted nftables must independently exercise the renderer's output.
Stage the extraction and projection move separately, but complete both before declaring the target
dependency boundary achieved.

**Acceptance:** the address selector imports neither nftables nor host configuration; the renderer reads
no topology or service inventory; contracts import no network feature implementation; the actual
configuration owner remains explicit; generated production
rules and source selections are unchanged by the split. Existing mutation tests must continue detecting
policy errors rather than treating shared helper reuse as independent proof.

## 5. Proposed target architecture

Keep the current concepts. Clarify their dependency direction:

```text
site inventory + placement policy
              |
              v
service declarations -----> validated, narrow fleet view
              |                         |
              v                         v
local provider adapters       fleet-level adapters
(DB, state, units)            (DNS, ingress, identity, monitoring)
              |                         |
              +------------+------------+
                           v
                 rendered configurations
                           |
                           v
              consumer-level verification
```

Suggested boundaries, not a mandatory mass rename:

| Boundary | Owns | Must not silently own |
|---|---|---|
| Inventory | Hosts, devices, addressing, placement, provider bindings | Application-specific database setup |
| Contract schemas | Valid vocabulary and semantic invariants | Personal fleet addresses or arbitrary defaults with no consumer |
| Pure projections | Address selection, identity/name calculation, normalized relations | Side effects or live discovery |
| Provider adapters | Caddy, Knot, Authentik, PostgreSQL, Restic, Prometheus specifics | A second copy of service intent |
| Roles | Explicit default feature bundles | Alphabetical identity/provider selection |
| Host composition | Hardware and deployment decisions | Reconstructed URLs owned by a provider |
| User configuration | User identity/profile and personal preferences | Global primary-user assumptions for every home |
| Checks | Independent expectations and failure cases | A claim of broader coverage than they execute |

A possible incremental layout is `inventory/` for site facts, `contracts/` for schema/invariants,
owner-local `lib/` directories for domain transformations, and the existing feature directories for
backend adapters. This does **not** require converting the whole repository to flake-parts, a framework
with path-driven semantics, a new deployment engine, containers, or a universal service factory.

## 6. Ordered implementation plan

Each work package should produce reviewable commits and its own acceptance evidence. Do not combine a
schema redesign, credential rotation and network cutover in one change.

### WP1 — Make the existing quality signal truthful

**Findings:** F01, F02, F03, F06, F10. **Effort:** M overall.

1. Fix CI trigger coverage and add a formatting check.
2. Add regression fixtures for alias ownership and forwarding verdicts, then repair the validators.
3. Resolve the broken deployment output and evaluate supported custom outputs explicitly.
4. Fix protocol-aware probes and unify the health-path spelling.
5. Preserve full warning output and update inaccurate check-coverage claims.

**Exit:** the deliberately broken examples in this review fail for the intended reason; valid current
hosts still evaluate; monitoring's generated target list contains no protocol mismatch.

### WP2 — Establish backup and state guarantees

**Findings:** F04, F05, relevant parts of F07. **Effort:** L.

1. Inventory state and backup disposition per service/host.
2. Implement one working dump/cleanup lifecycle with failure propagation.
3. Bind database backup freshness to the backup operation rather than only clock time.
4. Resolve ops-host state coverage and classify large replaceable media/download data.
5. Restore representative database-backed and file-backed applications in isolation.

**Exit:** documented RPO/RTO targets have restore evidence; exclusions are explicit; new backup behavior
is proven before old coverage is narrowed.

### WP3 — Align actual authority with the declared model

**Findings:** F08, F09, security parts of F20. **Effort:** L.

1. Prove minimum database grants using initialization and upgrade scenarios.
2. Define the secret decryption audience matrix and introduce appropriate file boundaries.
3. Verify real effective systemd hardening instead of counting local wrapper declarations.
4. State LAN limitations and operator/root authority precisely; review effective policies per host class.

**Exit:** permissions and decryption capabilities match documented ownership; normal service behavior and
operator recovery still work. Changes to authority have positive and negative consumer tests.

### WP4 — Make inventory and contracts honest, small interfaces

**Findings:** F07, F11-F18. **Effort:** L, split into independent extractions.

1. Produce the option-to-consumer inventory and retire or reject inert APIs.
2. Extract site inventory without changing rendered values.
3. Separate zones from trust levels and make provider selection explicit.
4. Establish a narrow fleet view, starting with one consumer and comparing output.
5. Split endpoint responsibilities along semantic boundaries.
6. Consolidate identity metadata and test a genuine second user.

**Exit:** representative alternate inventories/provider placements work; supported non-default options
have behavior; no alphabetical choice determines policy; artifacts remain equivalent for pure refactors.

### WP5 — Verify supported modes and operational promises

**Findings:** F03, F19-F21. **Effort:** M/L.

1. Add targeted enabled/disabled and non-default module fixtures.
2. Add packet-level allow/deny tests for representative caller classes.
3. Exercise resolver and relay failure scenarios in an isolated environment before claiming failover.
4. Measure each host class at the consumer path after eventual deployment.
5. Rewrite current-state documentation from the verified implementation.

**Exit:** coverage is explicit; invalid configurations fail; operational claims have reproducible evidence
and include known limitations.

### WP6 — Reduce maintenance cost and finish consistency work

**Findings:** F22-F24, remaining documentation cleanup. **Effort:** M.

1. Extract cohesive flake implementation blocks.
2. Record dependency-workaround retirement conditions and supported toolchains/platforms.
3. Resolve stale wording, the LibreOffice warning and locale-validation inconsistency.
4. Remove genuinely obsolete shims/features only after supported-reader and replacement checks.
5. Measure evaluation performance if it is an actual development bottleneck.

**Exit:** onboarding reflects commands that work; the composition root is readable; every remaining
abstraction has a consumer or a justified supported use case.

### WP7 — Make repository organization and module composition explicit

**Findings:** F25-F35, coordinated with F11, F15, F18 and F22. **Effort:** M/L across small steps.

1. Agree the filename/scope rules in section 9 and capture the current 82+7 discovered module paths.
2. Add the discovery fixture suite, including the measured accidental-import cases and path-dedup control.
3. Fix ineffective disable flags independently of any physical reorganization.
4. Centralize discovery and make `mkSystem` accept explicit module/user composition; retain current outputs.
5. Move one feature to explicit NixOS/Home Manager entrypoints, verify its positive/negative behavior,
   then apply the proven rule to the remaining features.
6. Extract inventory, baseline identity policy and operational app builders to their owned locations.
   Apply the file-level classification in section 9.9: place source policy with the topology contract
   and nftables rendering with the network area. Move endpoint-to-firewall projection into that area,
   keeping contracts independent of feature implementation. Capture and compare the generated rules
   before removing the original helper.
7. Apply naming cleanup with a migration table separating physical paths from stable public identities.
8. Re-run the same evaluation benchmark and document any actual improvement or regression.

**Exit:** folder changes cannot accidentally change feature activation; a helper named `default.nix` is
not a NixOS module; empty assignments and invalid paths are handled explicitly; the documented module
inventory is derived; the same supported hosts and users still compose correctly.

Do not temporarily discover both old and new entrypoint names indiscriminately. Use an explicit migration
mapping or a reviewed one-time conversion, and remove compatibility scanning when the conversion is proven.

Dependencies: WP1 establishes trustworthy checks for later work. WP2 and WP3 need targeted consumer
tests before behavioral changes. WP4 should begin only after relevant baseline projections are captured.
WP5 consolidates the stronger test coverage. Cosmetic work may be independent but should not delay P1s.
WP7's fixture/composition work can precede WP4's file extractions; its semantic disable fix belongs with
the early correctness work. File moves and behavioral changes should remain separately reviewable.

## 7. Definition of done

“Perfect” is not a stable acceptance criterion. The maintainable replacement is a bounded quality contract:

1. All supported flake interfaces evaluate; all five current hosts evaluate; required host builds pass.
2. Formatting, statix and deadnix run in CI on the intended change surface.
3. Every accepted custom option has meaningful behavior or an explicit unsupported-use error.
4. Critical checks have at least one relevant negative fixture; a false-green example cannot recur.
5. Names have unique owners; provider selection and user identity are explicit.
6. Protocol, ingress exposure, firewall permissions and monitoring agree for each endpoint class.
7. Every durable service has an explicit recovery disposition and relevant restore evidence.
8. Database/secret authority is explicit and tested at the consumer boundary.
9. Pure refactors preserve the selected rendered artifacts; behavioral changes state the intended delta.
10. Current specifications describe current behavior, supported scope and real limitations.
11. Discovery imports only the intended module scope; directory organization does not select identities
    or activate helpers; the supported file-kind and nested-module rules are tested.
12. Folder/API renames preserve stable service and persisted identities unless an explicit migration is
    intended; performance improvements are demonstrated at the claimed evaluation boundary.

Useful ongoing measures are the count of unsupported/inert options, documented exceptions, unexplained
warnings and failed negative fixtures; backup age/restore duration; and development evaluation latency.
Do not optimize for zero repeated lines, the smallest possible module, or the largest number of abstractions.

## 8. Reproduction notes

Run shell examples through Bash in this repository's fish-based operator environment. The following
commands are read-only evaluations/build checks; the mutation examples change only the evaluated input.

### Baseline and broken deployment leaf

```bash
nix flake check --no-build --no-update-lock-file
nix flake check --no-update-lock-file --print-build-logs
nix eval --raw --no-update-lock-file .#deploy.nodes.cld-edge-01.profiles.system.path
```

Expected baseline: success, with the warnings listed above. Expected final command at the reviewed
revision: exit 1, `attribute 'deploy-rs' missing`.

### Backup hook counterexample

```bash
nix eval --impure --raw --expr '
  let
    f = builtins.getFlake (toString ./.);
    h = f.nixosConfigurations.hom-srv-01.extendModules {
      modules = [ ({ pkgs, ... }: {
        my.contracts.provides.audit-fixture.backup.preDumpHook =
          pkgs.writeShellScript "audit-pre-dump" "exit 0";
      }) ];
    };
  in h.config.system.build.toplevel.drvPath
'
```

Expected for a working API: a derivation path. Observed at baseline: exit 1,
`services.restic.backups.daily.backupPreparePrune` does not exist. `--impure` here enables `getFlake`
on the explicit local path; the production configuration is not activated or modified.

### Network invariant mutation

```bash
nix eval --impure --json --expr '
  let
    f = builtins.getFlake (toString ./.);
    lib = f.inputs.nixpkgs-unstable.lib;
    router = f.nixosConfigurations.hom-srv-01;
    original = router.config.networking.firewall.extraForwardRules;
    changed = lib.replaceStrings [ "accept" ] [ "drop" ] original;
    result = import ./checks/network-invariants.nix {
      inherit lib;
      hostNames = builtins.attrNames f.nixosConfigurations;
      self.nixosConfigurations = f.nixosConfigurations // {
        hom-srv-01.config = router.config // {
          networking = router.config.networking // {
            firewall = router.config.networking.firewall // {
              extraForwardRules = changed;
            };
          };
        };
      };
    };
  in { mutationChangedRules = original != changed; inherit (result) violations; }
'
```

Expected for the documented reachability guarantee: non-empty violations. Observed:
`{"mutationChangedRules":true,"violations":[]}`. This specifically exercises the invariant function,
not a live firewall or a full modified NixOS module evaluation.

### Alias collision counterexample

```bash
nix eval --impure --json --expr '
  let
    f = builtins.getFlake (toString ./.);
    lib = f.inputs.nixpkgs-unstable.lib;
    endpoint = name: {
      canonicalDomain = "${name}.example.test";
      extraDomains = []; aliases = []; scope = "internal";
      fqdn = null; auth = "none"; publicExempt = null;
    };
    fixture = import ./contracts/naming/default.nix {
      inherit lib;
      config = {
        networking.hostName = "fixture";
        my.topology = {
          domain = "example.test"; ingressHost = "fixture"; devices = {};
          hosts.fixture.wireguardIpv4 = "192.0.2.1";
        };
        _module.specialArgs.flake.nixosConfigurations.fixture.config.my.contracts.provides = {
          first.endpoints.web = endpoint "first";
          second.endpoints.web = (endpoint "second") // {
            aliases = [ "first.example.test" ];
          };
        };
      };
    };
  in map (a: a.message) (builtins.filter (a: !a.assertion) fixture.config.assertions)
'
```

Expected: a Naming I2 failure identifying both owners. Observed: `[]`. The fixture invokes the actual
assertion implementation with explicit inputs; it does not claim a live DNS collision already exists.

### Inspect generated probes without dumping the full configuration

```bash
nix eval --impure --json --expr '
  let
    f = builtins.getFlake (toString ./.);
    jobs = f.nixosConfigurations.cld-edge-01.config.services.prometheus.scrapeConfigs;
  in builtins.concatLists (map (job: map (target: {
    inherit (target) targets;
    inherit (target.labels) host service;
  }) job.static_configs) (builtins.filter (job: job.job_name == "blackbox-http-local") jobs))
'
```

The resulting target list is the consumer-facing projection underlying F06. After fixing that finding,
capture the intended new list and validate it against the actual service protocols and health endpoints.

## 9. Organization, naming and discovery: concrete follow-up design

### 9.1 Verdict on the current organization

The outer structure is understandable. Keep the distinction between **deployment composition**, **feature
implementation**, **contracts**, **packages** and **personal configuration**. Replacing it wholesale would
create migration work without automatically improving those boundaries.

The most important organizational correction is to stop using directory accidents as an API. Today a
feature's registration depends on finding `default.nix` anywhere under a recursive root; the meaning of
`default.nix` also varies between a module, an overlay, an executable builder and a library export.
Those roles need explicit discovery boundaries even if ordinary Nix imports continue to use `default.nix`
where there is no ambiguity.

The recommended order is **define meaning → test the import contract → separate composition → move
files → rename selectively**. Cosmetic uniformity should not be mistaken for architectural consistency.

### 9.2 Placement rules

| File's responsibility | Recommended owner/location | Reason |
|---|---|---|
| Site host/device/subnet facts | `inventory/` | Data changes independently of schema and implementation |
| Host hardware and selected role/features | `hosts/<host-id>/` | Deployment boundary is explicit |
| Shared feature defaults | `roles/` | A role is a bundle, not a second inventory |
| Always-required account policy | Explicit baseline module imported by `roles/base.nix` | It should not impersonate an optional feature |
| Optional NixOS capability | `features/<area>/<component>/nixos.nix` | Its import context is clear |
| Reusable per-user behavior | Companion `home.nix`, only where needed | Home Manager logic has its own scope |
| Domain schema and invariants | `contracts/<domain>/nixos.nix` | Always-loaded contracts are distinguished from feature activation |
| Private parser/projector | Owning feature's `lib/` | Local knowledge stays local |
| Shared domain helper | The narrowest owning feature area's or contract's `lib/` | Multiple callers do not make domain logic global infrastructure |
| Cross-domain module/composition infrastructure | Root `lib/` | Discovery, system composition and generic module helpers have repository-wide responsibilities |
| Fleet audit or updater application | `apps/<app-name>/` | Operational programs are not hidden inside a generic library |
| Package derivation / package override | `packages/custom/` / existing overlay area | Packages remain separate from configured services |
| Icons, logos and wallpapers | `assets/` | Clearer than the overloaded root name `media/` |
| User identity and personal preferences | `user/<user-id>/` | Personal decisions stay out of reusable modules |
| Fast structural/semantic checks | `checks/` | Validation is discoverable from one place |
| Current behavior and conventions | `docs/` | Specifications remain distinct from this assessment |

The suggested always-required account policy can initially be a small `roles/base/identity.nix`
composition module; a new generalized policy framework is unnecessary. Schema can remain separately
owned by a contract. Do not create empty directories to satisfy this table.

Within `features/`, retain a small set of useful areas. `system` is OS/network/platform integration;
`services` is hosted applications and providers; `desktop`, `dev` and `media` are ergonomic groupings.
These labels are **navigation**, not execution permissions. A module is not confined to workstations
because its path contains `dev`; roles and activation predicates determine that.

Reclassify only obvious misplacements with a consumer-facing benefit. For example, move GeoIP beside
other services, and consider `system/containers/docker` for the daemon if the project wants a product-
explicit platform location. There is no need to rename every existing service option at the same time.

### 9.3 Suggested target tree

This is a proposed end-state illustration, not a set of files created by this review:

```text
flake.nix                         # Inputs, shared discovery, output composition
inventory/
  default.nix                     # Explicit data composition, never module auto-discovery
  hosts.nix
  devices.nix
  network.nix
hosts/<host-id>/
  configuration.nix              # Host entrypoint; keep the established discovery marker
  hardware-configuration.nix     # Generated hardware facts
  hardware-specific.nix          # Reviewed machine-specific overrides
  disk-config.nix                # Only on hosts using this disk declaration
roles/
  base.nix
  base/identity.nix              # Explicitly imported baseline integration, if extracted
  server.nix
  pc.nix
  desktop.nix
  notebook.nix
features/<area>/<component>/
  nixos.nix                      # Only automatic NixOS feature entrypoint
  home.nix                       # Optional Home Manager companion, explicitly registered
  lib/<concept>.nix              # Private pure implementation
  scripts/<verb-noun>.py         # Optional runtime implementation
  templates/<descriptive-name>   # Optional generated configuration templates
  assets/                       # Optional component-private static files
contracts/<domain>/
  nixos.nix                      # Typed contract and invariants, always registered
  lib/<concept>.nix              # Optional private helpers
contracts/topology/lib/
  access-sources.nix             # Backend-independent source selection owned by the topology model
  service-address.nix            # Consumer/provider address selection owned by the topology model
contracts/endpoints/lib/
  identifiers.nix                # Shared endpoint and service audience-group identifiers
features/system/networking/lib/
  nftables-render.nix            # Network-owned rendering helpers, no topology policy
lib/
  default.nix                    # Narrow helper interface, independent of Home Manager
  discovery.nix                 # Deterministic source-path discovery
  mk-system.nix                 # Thin system composition helper
  feature-dependencies.nix       # Existing requires semantics, with clearer naming
apps/
  network-audit/
  exposure-audit/
  update-custom-packages/
packages/
  custom/<package>/
  overlays/fix/<package>/
user/<user-id>/
  metadata.nix
  home.nix
  profiles/
checks/
  module-discovery.nix
  fixtures/                     # Test input; never part of feature discovery
  ...
assets/
docs/
```

For a component with independently enabled modes, keep meaningful nesting, for example
`features/services/attic/server/nixos.nix` and `.../client/nixos.nix`. Do not flatten these into ambiguous
names to save one directory level. Conversely, a single short module does not need `lib/`, `scripts/`
and `templates/` scaffolding.

Keeping `user/` singular is acceptable: renaming it to `users/` alone offers little value. Keeping
`hardware-specific.nix` is also reasonable once its boundary is documented. Consistency means a filename
has one understood role, not that every filename must be changed to a new favorite spelling.

### 9.4 Naming convention proposal

| Surface | Convention | Example / constraint |
|---|---|---|
| Directories and ordinary Nix files | Lowercase kebab-case | `home-assistant`, `module-discovery.nix` |
| Nix helper names and option fields | lowerCamelCase | `serviceAddress`, `primaryUser`, `interfaceName` |
| NixOS feature entrypoint | `nixos.nix` under a discovered feature root | Filename identifies scope, not enablement |
| Home Manager entrypoint | `home.nix` | Explicitly registered as an HM module |
| Package/library entrypoint | `default.nix` where directory import is useful | Outside NixOS auto-discovery semantics |
| Host composition entrypoint | `configuration.nix` | Preserve the current established convention |
| Private helper | Name the operation or concept | `blueprint.nix`, not `helper.nix` or `utils.nix` |
| Executable | Verb or operational task, kebab-case | `network-audit`, `update-custom-packages` |
| Python importable module | Valid Python module naming | Use snake_case where Python imports require it; do not force hyphens |
| Service/product component | Stable product or explicit capability name | `postgresql`; `dns` only if its abstraction is stated |
| Application mode | Nested role name where meaningful | `attic/server`, `authentik/outpost/ldap` |
| Option namespace | Stable public API independent of file movement | Moving a file need not rename `my.features.*` |
| Host/user ID | One authoritative inventory/key identity | Derive or assert `networking.hostName` / `username` |
| Endpoint and persisted identity | Stable semantic ID, consumer uniqueness checked | Never silently rename with a directory or display-label change |
| Display label | Human-readable; localization allowed | Distinct from DNS labels and secret keys |
| Documentation | Lowercase descriptive noun/topic | `architecture.md`, `operations.md` |

Resolve the broad names only where their responsibilities are actually unclear. `common` should not be
an invitation to put unrelated site data or third-party services there. `core` should identify a real
architectural boundary; otherwise `discovery.nix` and `mk-system.nix` are more informative.

For a proposed rename such as `vyrx-landing` to `portal`, first list these independent surfaces:
physical path, feature option, flake input, service contract ID, systemd unit, database, state directory,
secret key, DNS name and upstream package name. Mark each as **move**, **preserve** or **migrate**.
Changing all of them together would create unnecessary operational risk and obscure the reason for the
rename. Existing upstream names are not a consistency defect in a provider adapter.

### 9.5 Recommended discovery contract

Use **bounded automatic discovery for feature registration and explicit composition for policy**:

1. The composition root names the permitted roots, such as `features/` and `contracts/`.
2. Within those roots, only regular `nixos.nix` files are NixOS entrypoints.
3. Hidden directories and the agreed private directories (`lib`, `tests`, `fixtures`, `templates`,
   `scripts`, `assets`) are not traversed. Keep this policy in one place, with fixture coverage.
4. Discovery continues through ordinary organizational directories, including below a module that has
   independently enabled child modules. Parent registration is not parent activation.
5. Home Manager companions are registered explicitly by their owning integration/composition. Do not
   recursively treat every `home.nix` in the entire repository as a user configuration.
6. Paths remain paths until the standard module system imports them.
7. Discovery returns a deterministic list, optionally accompanied by derived provenance for diagnostics.
   It does not import/evaluate a module to guess whether it “looks like” a module.
8. Required roots and malformed markers fail loudly; absence is allowed only for a documented optional root.
9. Roles/host modules decide activation. The scanner does not inspect `config`, select identities,
   enable dependencies or infer semantics from directory order.
10. Derive a read-only inventory of module paths/scopes for diagnostics and checks from the same discovery
    result. Avoid a persistent generated registry that creates another list to maintain.

An explicit seven-contract import list is also manageable, but choose it as the authoritative contract
registration method if used. Do not require contributors to remember both an explicit list and an
automatic registration rule for the same modules.

This contract is intentionally simpler than a generalized plugin loader. Do not add regular-expression
path rewriting, configurable path-to-option generation, symlink resolution or a custom dependency graph
unless a supported use case requires them. Nix already owns module merging and import identity.

### 9.6 Composition and library interfaces

Make the flake or a small repository composition function discover source paths once, then share them
with all host constructors. Keep source discovery independently testable with a temporary fixture root.
The constructor should receive concrete module paths and user assignments instead of discovering new
policy while evaluating each host.

Illustrative responsibility split:

```text
discoverNixosModules(root) -> ordered module paths
discoverHostEntries(root)  -> host ID to entrypoint path
readUserMetadata(root)     -> declared identity data, without assigning it to hosts

repository composition    -> validates host/user assignments and provider bindings
mkSystem                  -> invokes nixosSystem with the explicit selected modules/package set
Home Manager integration  -> attaches explicit home modules to explicit users
```

These operations need not all become public library functions. Retain public exports only for real
consumers. The thin builder may be a repository-local function. Vendor input names such as
`nixpkgs-unstable` and `home-manager-unstable` belong at composition, while a genuinely reusable helper
receives the specific library/module it needs.

Share **module source paths**, not evaluated host configurations: different hosts need their own module
fixpoints. Share package sets only where architecture, overlays and package configuration agree.
Avoid caching evaluated modules globally or replacing Nix's lazy evaluation with eager `deepSeq` over
whole configurations. Force the consumer leaves needed by each check or benchmark.

### 9.7 Performance interpretation and repeatable measurements

Environment: local `x86_64-linux`, **Lix 2.95.2**, pinned nixpkgs library, existing store/source caches,
`NIX_SHOW_STATS=1`. No CPU affinity, load isolation or cold-cache protocol was applied. Measurements
therefore describe this review run; they are not stable service-level performance targets.

The microbenchmark used the production `findModules` implementation and actual feature/contract roots.
Both cases serialized identical lists for all five host names. It modeled the per-host versus shared
composition shape without evaluating any feature module. Six samples per case were retained after one
warm-up pair; case order alternated to reduce simple ordering bias.

The fleet benchmark explicitly forced each host's top-level derivation path in a fresh evaluator process
three times and verified identical returned derivations. Warnings were retained and read; both
LibreOffice deprecation warnings remained. It did not build or activate those derivations.

For a future measurement, separate these four boundaries:

| Boundary | What to force | What it tells us |
|---|---|---|
| Source discovery | Full ordered path list | Scanner behavior and overhead |
| One representative host | `system.build.toplevel.drvPath` | Useful development feedback latency, including cross-host dependencies |
| All current hosts | Map of top-level derivation paths | Fleet evaluation cost |
| Actual check/build workload | Supported `checks` and host build outputs | CI cost, which includes much more than discovery |

Run baseline and candidate against the same lockfile/toolchain and equivalent outputs. Separate first-run
fetching from repeated evaluation, report sample counts/ranges, and record workload/load conditions.
Interpret allocator statistics correctly; use a separate process memory measurement if peak RSS matters.
Investigate regressions as well as improvements. An optimization that removes schema or check coverage
is not an equivalent optimization.

Read-only examples for the two principal evaluation boundaries:

```bash
# Execute this block through Bash; the local operator shell is fish.
bash -s <<'BASH'
set -euo pipefail
NIX_SHOW_STATS=1 nix eval --impure --json --expr '
  let
    f = builtins.getFlake (toString ./.);
    lib = f.inputs.nixpkgs-unstable.lib;
    loader = import ./lib/core/module-loader.nix { inherit lib; };
  in map toString ((loader.findModules ./contracts) ++ (loader.findModules ./features))
'

NIX_SHOW_STATS=1 nix eval --impure --json --expr '
  let f = builtins.getFlake (toString ./.);
  in builtins.mapAttrs (_: h: h.config.system.build.toplevel.drvPath) f.nixosConfigurations
'
BASH
```

For repeated measurements, prefer a small script file using an argument-array subprocess invocation.
The review's fixture driver and measurement output were kept under
`/tmp/opencode/nixfiles-discovery-review*`; those temporary files are not part of the repository's tests.
Promote the relevant cases into the focused check described in F34 rather than depending on their presence.

### 9.8 Structural test matrix and migration evidence

| Case | Required result after the discovery change |
|---|---|
| Empty valid root | Empty list |
| Missing required root | Clear failure with root path |
| One regular NixOS marker | Exactly one module path |
| Parent and independent nested child markers | Both registered in documented order |
| Helper `lib/default.nix` | No additional NixOS module |
| Hidden/test/template directory | Excluded under the declared rule |
| Marker that is a directory or disallowed symlink | Clear structural error |
| Ordinary Home Manager companion | Registered in HM scope only, by its owner |
| Same child path via parent import and explicit registration | Standard Nix path deduplication preserved |
| System feature disabled | Its defined system effects disappear |
| One of two users enables a home feature | Only that user receives the intended home effect |
| Explicit empty user assignment | No users assigned through discovery fallback |
| Missing or duplicated selected user | Clear identity/composition error |
| Pure helper/file reorganization | Same intended imports and consumer-facing artifacts |

Before changing filenames, capture the discovered path set and map each old entry to its new entry.
Compare evaluated service units, endpoint/DNS projections, firewall rules and home assignments across
the affected hosts. A physical move can change source-location metadata, store paths or generated-source
names, so whole derivation-path equality is useful when it holds but is not a universal requirement for
a semantics-preserving file move. Explain differences at the consumer boundary instead of either
ignoring them or demanding impossible byte identity of source provenance.

Apply one proven convention consistently, then update `AGENTS.md` and the present-state architectural
specification with that actual rule. The documentation should say exactly what the importer imports,
what it ignores, what constitutes an independent feature and where activation decisions belong.

### 9.9 File-level placement audit: owner first, technology second

**A file mentioning nftables can be correctly placed in a library. A file named `helper.nix` can still
be misplaced there.** Classify what the file owns, its interface and its real consumers before deciding
its path. The same applies to PostgreSQL, Caddy, Authentik and other technology-specific code.

Use three questions together:

1. **What does it produce?** Site data, an option schema, policy-derived data, backend text, a NixOS/HM
   module, a package or an operational executable are different responsibilities.
2. **Who owns the meaning?** The inventory, a contract, one component, a shared domain or repository
   composition should be identifiable. Multiple callers do not automatically make code domain-neutral.
3. **Who actually consumes it?** Shared production logic can belong in a domain library. A feature helper
   used only by that feature and its tests normally remains with that feature; the test alone is not a
   reason to promote it into the root library.

**Placement rule:** put helpers at the narrowest shared domain owner. Use root `lib/` for genuinely
cross-domain infrastructure, not simply for anything used by more than one file. Thus network siblings
can share `features/system/networking/lib/`, while a private firewall helper belongs under
`features/system/networking/firewall/lib/`. Contract-owned domain logic belongs beside its contract.

Nix expressions are declarative, and even a function producing a derivation is evaluated without running
the resulting program. Consequently, “it is a Nix function” or “it is pure at evaluation time” is not a
sufficient placement rule. The artifact and responsibility it represents matter as well.

#### Concrete disposition of reviewed files

All destinations below are proposals. Source paths name the current files; no implementation move was
performed as part of this review.

| Current source | Actual responsibility | Recommended disposition |
|---|---|---|
| `lib/nftables.nix` | Shared nftables formatting **and** trust-source selection | Split into `features/system/networking/lib/nftables-render.nix` and `contracts/topology/lib/access-sources.nix` as F35 specifies |
| `lib/addresses.nix` | Choose a service address for a particular consumer/provider pair using topology | Proposed `contracts/topology/lib/service-address.nix`, alongside the extracted topology model; shared consumers do not change its domain owner |
| `lib/endpoints.nix` | Normalize endpoint IDs and derive/recognize service audience-group IDs | Proposed `contracts/endpoints/lib/identifiers.nix`; shared service-identity rules stay with their contract owner |
| `lib/features.nix` | NixOS feature dependency enablement/assertion helper | Proposed `lib/feature-dependencies.nix`; do not imply it implements or discovers all features |
| `lib/core/module-loader.nix` | Discover paths; it does not load or evaluate the modules | Proposed `lib/discovery.nix`; exports should identify NixOS scope once the new marker contract is adopted |
| `lib/core/system-builder.nix` | Repository-bound system and home composition | Separate discovery/policy first; retain a thin `lib/mk-system.nix` helper if useful, with site composition owned at the flake boundary |
| `lib/default.nix` | Home-Manager-dependent factory exposing only `mkSystem` | Make it an accurately scoped, deliberate API; pure helpers should not require Home Manager merely to import them |
| `lib/helper.nix` | Compatibility forwarding | Retire after supported-reader verification; “helper” communicates no responsibility |
| `lib/audit/default.nix` | Build two fleet-aware operational programs from evaluated configurations | Move executable ownership to `apps/network-audit/` and `apps/exposure-audit/`; share only the genuinely common fleet projection rather than copying the entire builder |
| `lib/updaters/` | Package-update application, runtime scripts and its tests | Co-locate under `apps/update-custom-packages/`; keep its test hooked into `checks`, without confusing discovery of tests with discovery of modules |
| `features/system/networking/firewall/default.nix` | Enable nftables-backed NixOS firewall and forwarding filtering | Correct configuration owner; rename entrypoint to `nixos.nix` only as part of the agreed discovery migration |
| `features/services/authentik/lib/blueprint.nix` | Authentik-specific blueprint constructors and model vocabulary | Keep local to Authentik; independent tests may import the helper without making it a general fleet library |
| `features/services/esphome/templates/sonoff-basic.nix` | Parameterized ESPHome device template | Keep in ESPHome templates; the fact that it is a Nix function does not make it a root-library utility |
| `features/system/networking/topology/default.nix` | Mixed site data, schema and projections | Split according to F11/F12; literals to inventory, schema to its contract, reused policy transformations to a clearly named domain helper |
| `contracts/endpoints/default.nix` | Endpoint schema plus multiple projections | Split along F15; renaming or moving the whole file cannot fix mixed ownership |
| `packages/overlays/fix/paperless-ngx/default.nix` | Package override | Keep in package overlays; the corresponding service feature is not the owner of a general package build fix |

The owner-local library folders in the proposed tree group actual responsibilities; they are not a mandate
to create an entire hierarchy of empty `network`, `security`, `identity`, `storage` and `utils` folders.
Likewise, do not split every one-line helper into a file. The nftables split is justified by different
dependencies and consumers, not by a maximum file size.

#### Expected dependency direction for the nftables case

```text
topology + endpoint/device declarations
                  |
                  v
     backend-independent source selection  <--- policy checks
                  |
                  v
      network-owned endpoint / routing adapters
                  |
                  v
          nftables text renderer
                  |
                  v
      NixOS firewall rule options

firewall feature: selects/enables the backend and default filtering behavior
```

Contracts supply declarations to the network area; they do not import its rendering implementation.
The renderer should know how a set or a rule is spelled, not which hosts deserve access. Source selection
should know the declared categories and addresses, not how nftables spells a match. The adapter combines
those facts. The NixOS feature owns the system settings that activate the firewall.

A backend-specific shared renderer is compatible with an agnostic policy layer precisely because that
dependency is named and bounded. Hiding nftables behind a supposedly universal `firewall-utils.nix`
would make that boundary less honest. The recommended location is
`features/system/networking/lib/nftables-render.nix`: the network area can own a helper shared by its
firewall and routing implementations. It need not be private to one leaf feature to qualify for a local
`lib/`. Reserve `features/system/networking/firewall/lib/` for implementation genuinely private to that
feature, and keep backend-independent source policy with the topology/access model.

#### Naming and placement acceptance rules

- A path should answer “what does this own?”; its exported interface should answer “what does it need
  and produce?”. `nftables-render.nix` is more informative here than `nftables.nix` or `utils.nix`.
- Put site literals with inventory/policy owners, not in generic-looking defaults. Pure policy helpers
  may consume that inventory explicitly without embedding the site's data.
- Keep implementation-specific vocabulary visibly implementation-specific. Do not call a text joiner
  a validator or a verified firewall compiler.
- A helper receiving a new unrelated responsibility should be reconsidered even if its file remains
  short. A long but cohesive implementation does not become misplaced solely due to length.
- Search actual readers before moving or deleting exports. The unreferenced `portSet` is a candidate
  for cleanup, not proof that all external consumers are absent.
- For the first nftables extraction, compare rendered `extraInputRules` and `extraForwardRules` on each
  host, plus the selected source sets. The expected delta is **none**. Correctness improvements to the
  rule model are separate changes with their own expected delta and negative tests.
- Tests for policy correctness must retain independent expectations. Reusing the same source-selection
  helper in production and tests is useful plumbing reuse, but cannot alone validate that helper's policy.

This turns “everything in the right place” into a reviewable rule: **one understandable owner, an honest
interface, intentional consumers and a path that describes the responsibility**.

## 10. Decision record (2026-09-27)

The decisions taken after the review. They are the contract the work packages follow; a later decision
supersedes one by date, not by silently editing this table.

| # | Decision | Consequence |
|---|---|---|
| D1 | NixOS modules are discovered by the name `nixos.nix`; Home Manager companions are `home.nix`; `default.nix` stays the entrypoint for importable packages and libraries. | The scanner looks for `nixos.nix` only, under `features/` and `contracts/`. A helper `lib/default.nix` can no longer become a module by its filename. |
| D2 | Site facts live in a top-level `inventory/`, composed explicitly and never auto-discovered. | Hosts, devices and subnets move out of the topology feature; the schema stays with the topology contract. |
| D3 | Operational programs move to `apps/`. | `apps/network-audit`, `apps/exposure-audit`, `apps/update-custom-packages`; `lib/` keeps evaluation-time helpers only. |
| D4 | A feature that needs Home Manager logic gets its own `home.nix`, registered explicitly. | The NixOS entrypoint registers the schema; the per-user implementation has its own scope and its activation is honest. |
| D5 | `vyrx-landing` is renamed internally to `portal`; public identities stay. | The directory and option path change; service id, DNS name and state/secret paths do not. |
| D6 | The library names its responsibilities. | `lib/discovery.nix`, `lib/mk-system.nix`, `lib/feature-dependencies.nix`; `lib/helper.nix` and `lib/core/` are dissolved after their readers move. |
| D7 | Contracts declare reachability; the network area projects firewall rules. | `contracts/endpoints` stops importing nftables helpers; the renderer lives in `features/system/networking/lib/`, source selection with the topology contract. |
| D8 | A zone is a reference with an existence assertion; `trustLevel` stays a policy category. | Two zones may share a trust level; an unknown zone fails the build. |
| D9 | CI validates the whole evaluable surface. | Path filters include `checks/**`, `secrets/**`, `.sops.yaml` and `.githooks/**`; formatting is a flake check; the Attic cache is a documented prerequisite. |
| D10 | `x86_64-linux` is the supported platform, stated as such. | Multi-architecture outputs are not added without a real second target and package/hardware support. |
| D11 | User assignment is explicit per host. | Alphabetical discovery of the primary user is removed; a missing or duplicated assignment fails clearly. |
| D12 | The update workflow keeps its direct push, but records the tested revision. | Behaviour is unchanged; the evidence of what a batch was tested against becomes explicit. |
| D13 | Backup policy. | Media and downloads are explicitly excluded; `cld-ops-01` is intentionally without Restic (its state is regenerable or valueless) and that is declared, not omitted; a PostgreSQL logical dump is authoritative and the data directory is not file-backed-up; RPO 24 h; class-A services get a restore drill. |
| D14 | Separate contracts by domain under one service declaration; retain and implement telemetry. | Monitoring moves from endpoints to telemetry through validated endpoint references; identity and portal get their own schemas. Feature-owned projections must preserve generated artifacts during structural extraction. See §10.5. |
| D15 | Target public API is service-centric: independently named endpoints, publications, identity integrations, observations, presentation, storage, backup and requirements. | Domain references are typed and validated; endpoint owns only listener and direct reachability facts. Ingress, identity and presentation no longer rely on nesting their declarations inside endpoints. Preserve public service ids, names and policy as each projection migrates. See §10.6. |

### 10.1 Consequences for the findings

- **F05** — the `cld-ops-01` observation is a *decided exclusion* (D13), not a coverage gap: the
  requirement becomes that every absence is declared, and that a PostgreSQL dump stays the authority
  while its destination directory (not the data directory) is inside the backup scope.
- **F04** — the pre-dump lifecycle is fixed against the pinned NixOS options (`backupPrepareCommand` /
  `backupCleanupCommand`), not the nonexistent `backupPreparePrune`, and dump freshness is bound to the
  backup run rather than to an independent clock.

### 10.2 Implementation incrementsCorrections before churn, so nothing is touched twice:

| Increment | Scope | Status |
|---|---|---|
| 1 | F02 naming ownership, F10 CI/hook/format check, this decision record | done |
| 2 | F06 protocol-aware probes and one health-path spelling | done |
| 3 | F04/F05 backup per D13: a working hook lifecycle, honest tiers, an explicit no-backup decision | done |
| 4 | F01 deployment surface (+ `operations.md`) | done |
| 5 | D1 discovery contract and fixtures, then the marker migration | done |
| 6 | D3/D5/D6 extractions, D4 `home.nix` split, D7 renderer/projection split | done |
| 7 | D2 inventory extraction, D8 zone-vs-trust, D15 public API migration, F07 inert options, F15 endpoint segregation, F11/F12 topology split and validation | done (inventory/ composes subnets/hosts/devices explicitly; zones are validated subnet references; per-domain fixtures green; F13/F14/F16/F17/F18/D11 done in following commits; live drills in increment 8 stay open) |
| 8 | F08/F09 and WP2 restore drills, then F19/F20/F21 verification and documentation | open |

### 10.4 What is deliberately not done yet, and why

The remaining findings are not blocked by effort; each needs a *verification* that a build cannot give,
and shipping them without it would repeat the failure mode `docs/practices.md` describes.

- **F08 minimum database grants.** Narrowing the `-arr` roles from `superuser` to database ownership
  changes what a running PostgreSQL may do. It must be proven by starting each application against a
  restored database and running its migrations - a live drill on `hom-srv-01`, not an evaluation.
  *(Increment 8.)*
- **F09 secret decryption scope.** Partitioning `secrets/secrets.yaml` changes which host can decrypt
  what, and the existing file is already encrypted to every recipient. It needs a disposable
  recipient-matrix test and a rotation decision before it is safe; that is an operational step with the
  operator in the loop. *(Increment 8.)*
- **F05/WP2 restore evidence.** The declared artifact and its exclusions are correct and proven, but
  "a dump can be restored" is a claim only a restore drill can make. *(Increment 8.)*
- **D2/F11 (done).** Site facts live in `inventory/` (subnets, hosts, devices), composed
  explicitly by path in `lib/mk-system.nix` and never auto-discovered. The topology module keeps
  schema, derived policy and validation; inventory files carry plain definitions with a documented
  extension policy. A synthetic second inventory evaluates through the untouched schema.
- **D8/F12 (done).** A zone is a validated subnet reference, not a trust-level enum: unknown zones
  fail with a named message, two zones may share a trust level (proven by fixture), and no
  mechanism reads level order (the lattice-order claims are retracted to convention). Inventory
  validation covers IPv4 syntax, subnet-CIDR syntax, address uniqueness, device/overlay/gateway
  subnet membership and DHCP-served `/24` shape; IPv6 containment is documented out of scope and
  matched exactly instead. Cloud public addresses and provider gateways are deliberately exempt
  from zone membership, with the reason stated where the exemption lives.
- **F13 (done).** Providers are derived as the unique host with the role (authentik core, monitoring
  hub, crowdsec master) via `fleetConfigs.uniqueHost`; zero or several fail loudly. The core URL
  uses the core's declared listen port, outpost/ldap/hub/master bindings that were literals are
  derived (both manual coreAddress settings removed), the alloy loopback fallback throws, and
  agentless nodTarget addresses come from the inventory. All bindings byte-identical to HEAD.
- **F14 (done).** One fleet view (`lib/fleet-configs.nix`, injected via `mk-system.nix`): all
  consumers read `fleetConfigs.systems`/`providesOf`, standalone evaluation is explicitly
  unsupported with a domain error, and a fixture proves pass-through plus loud null/empty
  rejection. All nine projections, the Authentik blueprints and the portal artifacts are
  byte-identical to the pre-change revision on all hosts; full-fleet evaluation is unmeasurably
  unchanged (eval-hosts build 40.3s before and after).
- **F16/F17/F18/D11 (done).** The mesh interface name is projected from its option with a rename
  fixture; list-order identity picks are gone (explicit primary, one LDAP integration, no
  alphabetical builder fallback); users come from one `usersDir` discovery with per-entry
  Home Manager identity. F15 (endpoint segregation) and the F07 inert options (`websocket`,
  PostgreSQL `extensions`, Redis consumer) were resolved by the D15 migration.

The invariants of this session - one finding per commit, a proof at the consumer level, structure never
mixed with behaviour - hold for every increment above.

### 10.3 A methodological note, recorded because it cost an hour

The malformed-marker control was first written wrong and still looked like evidence. The probe evaluated
`loader.findModules` on a malformed tree and grepped the output for the throw message - but the throw
fires inside list construction, the outer expression never forced it, and the grep matched nothing for
the wrong reason. A negative test that cannot fail is not a test (cf. `docs/practices.md` §4.1: a
missing tool, a guessed name and a real negative look identical at the point of measurement).

The corrected form lives in `checks/module-discovery.nix`: `builtins.tryEval (builtins.deepSeq …
true)` observes the throw *inside* the check derivation, and a stray-module control proves the same
check fails loudly when it should. The rule for the remaining increments: a negative control must name
the failure it expects *and* demonstrate it by breaking the fixture, not by asserting over unevaluated
output.

Residual, deliberately deferred: PostgreSQL's dump is still produced by its own timer (02:00) rather than by
the backup job's `preBackup` hook. The artifact and the exclusion are correct now; binding freshness to the
run changes what a live backup does and needs a restore drill on `hom-srv-01` before it ships, so it is a
task with its own verification rather than part of this record.

### 10.5 D14 — Domain-owned contracts and implemented telemetry (2026-09-27)

Agreed design, implemented for the supported observability surface. This supersedes the conversational recommendation to delete
telemetry and the claim that all monitoring belongs permanently in the endpoint contract. An unused
schema demonstrates missing implementation, not an invalid domain boundary. An endpoint reference
avoids duplicated listener facts; it is not itself a DRY violation.

`my.contracts.provides.<service>` remains the common declaration site:

| Domain | Owns | Schema location |
|---|---|---|
| Endpoints | Listener port, transport and application protocol, direct network reachability | `contracts/endpoints/` |
| Publications | DNS identity, exposure plane, HTTP ingress policy and audience, referencing an endpoint | `contracts/publications/` (+ `contracts/ingress/`, audience in `contracts/identity/endpoint.nix`) |
| Telemetry | Named probes and metrics scrapes referencing an endpoint | `contracts/telemetry/` |
| Identity | OIDC/LDAP integrations referencing a publication; directory consumers | `contracts/identity/` |
| Portal | Presentation tiles referencing an endpoint, service-level readouts and actions | `contracts/portal/` |
| Storage | Persistent and regenerable data | `contracts/storage/` |
| Backup | Backup scope and lifecycle | `contracts/backup/` |

Schemas and backend-neutral validation belong to their contract domain. Prometheus, Caddy, Authentik
and portal features own their respective backend projections; shared helpers stay with the domain
that owns their knowledge. Splitting schemas does not require splitting a service declaration across
multiple files.

Telemetry references named endpoints of the same service and derives addresses and ports from them.
Probe kind, health path, scrape path, intervals and observation categories belong to telemetry.
An endpoint may have no monitoring or several observations; logs and many alerts need no endpoint.
Model the application protocol explicitly alongside transport: TCP alone cannot distinguish HTTP,
SSH and PostgreSQL. Replace the universal HTTP-probe default with protocol-aware validation and
intentional observation policy.

Implementation and acceptance:

1. Move the existing working monitoring declarations and all readers to telemetry together. Keep one
   authoritative model rather than two independently configurable monitoring APIs.
2. Validate endpoint references and probe/protocol compatibility during evaluation. Negative checks
   must demonstrate that unknown references and incompatible combinations fail clearly.
3. Compare generated probe targets and scrape jobs before and after extraction for every host;
   structural moves preserve these artifacts. Protocol-policy corrections have separately stated
   expected changes and checks.
4. Extract identity and portal responsibilities from endpoints with equivalent consumer-level
   comparisons of their generated configuration.
5. Every retained telemetry field needs a real consumer and a behavioral example. Implement needed
   log/alert capabilities or remove unsupported fields; retaining telemetry does not justify inert
   options or speculative functionality.

The implemented API is `my.contracts.provides.<service>.telemetry.{probes,scrapes}.<name>`, with an
explicit `endpoint` reference in each declaration; no HTTP probe is synthesized by a listener.
The endpoint name is the reference; neither address nor port is repeated. Identity integrations use
`identity.{oidc,ldap}.<name>.publication`; presentation tiles use `presentation.tiles.<name>.endpoint`;
publications use `publications.<name>.endpoint` and own DNS identity, ingress policy and audience.
Ingress policy lives in `contracts/ingress/endpoint.nix`, service dependency references in
`contracts/dependencies/`, LDAP consumer schema and audience naming in `contracts/identity/`,
and the Caddy/CrowdSec-specific publication extensions with their respective features.
HTTP/TCP probe and metrics-scrape declarations have actual consumers; the old unconsumed
telemetry `logs`, `alerts`, metrics scheme and interval options were removed rather than
promising behavior that does not exist, as were the unread `websocket` ingress flag, the
unprojected PostgreSQL `extensions` list and the unimplemented Redis consumer (`instance`,
`dbIndex`) - no declaration in the tree set any of them. Applications declare a distinct
application protocol where needed; HTTP probes and scrapes require `applicationProtocol = "http"`,
and TCP probes reject UDP.
The supported collector's scrape jobs and the portal inventory/adapters were compared to the
previous revision at their generated output boundary. This evaluation proof is not a live
monitoring or incident-response test.
After the publication migration, every host's Caddy vHosts, firewall rules, DNS records,
Authentik blueprints, Prometheus scrape jobs, LDAP consumer values, service dependency
references and portal inventory/adapters were compared byte-for-byte against the pre-D14 revision.

### 10.6 D15 — Service-centric contract API (2026-09-27)

D15 supersedes the idea that separating schema *files* suffices. An option physically declared by an
identity or ingress module still belongs to the endpoint API if its public path is under
`endpoints.<name>`. The target is one cohesive `provides.<service>` declaration with sibling
domains and explicit references, not one application file per domain and not a global resolver that
silently joins everything:

| Domain | Declaration | Required relationship |
|---|---|---|
| Endpoints | `endpoints.<id>` | Own listener port/socket, transport, application protocol and direct network reachability. |
| Publications | `publications.<id>` | Reference an endpoint; own DNS name, exposure and HTTP termination. A public DNS record need not imply an HTTP proxy. |
| Access | Within a publication or an explicitly reachable resource | Own audience, forward-auth and exemptions; publication visibility never confers authorization by itself. |
| Identity | `identity.oidc.<id>` / `identity.ldap.<id>` | Reference the application/publication as appropriate; own provider integration and resolved redirect/consumer data. |
| Telemetry | `telemetry.probes.<id>` / `telemetry.scrapes.<id>` | Reference an endpoint; neither duplicate its port nor infer observations from TCP. |
| Presentation | `presentation.tiles.<id>` plus service-level readouts/actions | Reference an endpoint; own names, localized copy and capabilities. |
| Requirements | `dependsOn` and `consumes` | `dependsOn` names fleet-wide service ids (validated); `consumes` references capabilities/services, never select a provider by list order. |
| Storage/backup | Existing service-level contracts | Own durable data and restorable artifacts independently of endpoints. |

Two publications may eventually share an endpoint while differing in audience and name. A service
without a public HTTP face can still publish DNS, expose a direct listener or declare telemetry.
Identifiers visible outside the repository (DNS names, Authentik slugs, client IDs, Prometheus job
names, secret/state paths) are preserved unless an explicit behavior change is separately specified.
Unknown references, incompatible protocols and conflicting bindings fail evaluation with a named
declaration. The success criterion is the consumer's emitted firewall, Caddy, DNS, Authentik,
Prometheus and portal artifacts, compared before/after by host class, not merely evaluation of a new
schema. The service's actual listener and its endpoint contract must share one configured port.

**Current boundary (implemented):** Named probes/scrapes, publication-referenced OIDC/LDAP
integrations, endpoint-referenced presentation tiles and endpoint-referencing publications have
migrated. Their generated Prometheus, portal, LDAP, Authentik, Caddy, DNS and firewall artifacts
are byte-equivalent to the pre-migration revision. `endpoints.<id>` owns only listener facts.
Remaining work is tracked in increment 7; the file-level extraction is complete and the public
option paths above are the binding API.
