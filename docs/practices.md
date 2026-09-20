# Engineering practices

`architecture.md`, `naming.md` and `identity.md` describe **what** this configuration is.
This file describes **how good** it has to be, what that means concretely, and what is still
missing. It is a working document: it shrinks as the gaps close, and it gets deleted when empty.

---

## 1. What the bar means — concretely, not as an adjective

| Term | Concrete meaning | Verified by |
|---|---|---|
| **akademisch / professionell** | every claim in a doc can be checked against the system or against the source of truth | the claim names the artefact it describes |
| **clean** | no dead code, no dead data, no field that claims something that does not exist | `deadnix --fail`; and "who reads this?" asked *before* a declaration is written |
| **solid** | failures are visible and loud; nothing is carried along as broken | `systemctl --failed` empty, deploys return `exit 0` |
| **DRY** | every fact has exactly one declaration; everything else derives | grep the fact; if it appears twice, one of them is wrong in the long run |
| **konsistent** | code and running state agree, and the fleet runs one revision | deployed generation vs. the repository's revision, per host |
| **agnostisch** | a component names its *intent* (scope, subdomain, zone), never an absolute address or a name owned by another layer | a service contract carries no addresses; a host carries no service names |

The bar is behavioural, not stylistic: it exists because every violation of these rules has already
cost us something real (see §4).

---

## 2. Acceptance criteria — "done" means all of these hold

**A1 — Deploys report the truth.** `systemctl --failed` is empty on every host and
`nixos-rebuild switch` returns `exit 0`. Until then no deployment verifies anything.

**A2 — No feature declares a name it does not own.** A `domain` option survives only where the name
is genuinely independent of an HTTP endpoint (`mail`: an SMTP/IMAP hostname). Everything else reads
the naming engine's derived `canonicalDomain`.

**A3 — The fleet runs one revision.** Every host is at the same commit; no host lags the repository.

**A4 — No scaffolding.** No `migration` blocks, the I11 report is empty, the migration guard is gone,
the connectivity question is answered by the normal topology.

**A5 — DNS equals code.** The reconciler has removed the transitional public labels; what DNS
answers is what the repository declares.

**A6 — Every credential has one owner and one path.** A fresh fleet key with its own path,
`~/.ssh/config` no longer pointed at a service credential, LAN certificates valid, one password per
identity across the fleet — and the declaration of that password actually enforced, not merely
stated.

---

## 3. The method that works here — and the two times it was ignored

For every change that removes or replaces something:

1. **Find all readers** of the fact (grep, and read what each one does with it).
2. **Replace** the readers, feature by feature, with the derived value.
3. **Prove equivalence before deleting**: compare the derived state before and after
   (`nix eval --apply builtins.hashString …` on the affected configuration values), never "it looks
   right".
4. **Only then delete** the option, the field or the rule.

Two outages on 2026-09-19 came from skipping step 3: the FRITZ!Box/sshd cutover (the old address was
dropped before the new path was proven) and the NAT rule (`networking.nat` emits nothing without
`internalIPs`, and the working rule was deleted anyway). Both were caught by a check that already
existed — and misread. The lesson is not "be careful", it is "prove the replacement produces the same
state, and read your own evidence twice".

Two further failures that evening were of the same kind, in the *diagnosis* rather than the change,
and both were reported as findings before being re-checked:

- **A broken tool produced a verdict.** `mkpasswd` did not exist in the environment, so the variable
  it was supposed to fill stayed empty, and the comparison `[ "$NEW" = "$CHECK" ]` was true because
  both sides were empty. That "mismatch" was written up as a credential drift. The drift was real,
  but its cause was not where the broken test pointed. **Rule: a check that cannot fail loudly is not
  a check.** Compare against a non-empty expectation, and treat an empty result as failure.
- **An accidental empty secret.** The same missing tool wrote an *empty* value into the SOPS store,
  which with `mutableUsers = false` would have locked every account out. It was caught in the same
  turn and restored from git. **Rule: never write a derived secret without a read-back verification,
  and never turn on enforcement in the same change that produces the value it enforces.**

---

### 4.1 The pattern behind almost every wrong finding: a negative from an unverified source

None of the four outages was a mysterious system. Each was a *statement* that nothing tied to the
state — and the ones that cost the most were the ones I produced myself:

| Instrument | What it actually said | What I read |
|---|---|---|
| `mkpasswd` missing | empty string | "the hashes match" → an empty hash was written to SOPS |
| `dig` missing | no output | "the resolver does not answer" |
| `systemctl is-active migration-guard.timer` (invented unit name) | `inactive` for a unit that does not exist | "the migration guard is disarmed" |
| `test -r /var/log/caddy/access.log` (invented filename) | the file does not exist | "crowdsec cannot read the logs" |
| my own script ending on `echo` | `exit 0` while `nixos-rebuild` had failed | "the deploy succeeded" (twice) |
| `ip -4 neigh` on `hom-srv-01`, counted with `| wc -l` | 12 lines, 11 of them `FAILED` or `INCOMPLETE` | "11 devices are still on the old subnet" |
| an imagined context figure, stated twice | — | "I have 88% used" / "I have 17% free" |

The root cause is not carelessness. It is that **a missing tool, a guessed name and a real negative
look identical at the point of measurement**. The remedy is procedural and cheap, and it is now the
rule for this repository:

- every negative claim names the command that *would* have produced a positive;
- no measurement counts until the instrument itself has been shown to work (does the file exist, does
the unit exist, is the tool there);
- in scripts: `set -euo pipefail`, never end on a bare `echo`, and derive the exit code from the checks
  rather than from the last statement;
- for a refactor, prove equivalence at the *delivered* level (rendered values, unit counts), not at the
  level of the options being changed — and read leaves, never whole subtrees, because forcing a subtree
  evaluates options nobody evaluates in production;
- a unit state that is not `active` (or not `success`, for a oneshot) is a **failure**, not a phase. A
  `caddy` stuck in `reloading` answered nothing for any vhost on that host — from the LAN and through
  the ingress alike — while reading like an intermediate state in a rollout script. The following
  script checks `[ "$(systemctl is-active caddy)" = active ]` and aborts otherwise; the earlier ones
  printed the state and moved on.

### 4.2 A symptom treated three times, because the documented mechanism was never read

The LAN zone model — the inventory decides the address range a device lands in — took three rounds,
because every round fixed something visible instead of reading the mechanism that produced the
behaviour:

| Round | Belief | How it was "verified" | What was actually true |
|---|---|---|---|
| 1 | the MAC test `hexstring(pkt4.mac,'')` returns a string form that never compares equal | Kea parsed the file, the classes were in the rendered config, exactly one subnet was classless | the class test was never observed *matching*. Kea's validator had been printing `DHCPSRV_CLIENT_CLASS_DEPRECATED` on **every start** — through a filter that looked for `ERROR` only |
| 2 | the unrestricted default subnet shadows class-restricted ones later in the list | plausible-sounding reasoning about "the first eligible subnet", plus one ambiguous measurement | no documentation was consulted at all; the measurement was equally consistent with the classes never being evaluated |
| 3 | the direct `pkt4.mac == 0x…` form and the corrected order | Kea accepted and validated it | still nothing changed on the wire - because the selection never reached the classes |

The actual answer was in the documentation the whole time. ARM **8.6**: for a directly connected
client the server selects the single subnet the *receiving interface's address* falls into, and "the
subnet selection mechanism described in this section is based on the assumption that client
classification is not used". The gateway's interface carries an address of every zone at once, so one
zone won for every client, deterministically. ARM **8.4** names this deployment exactly — "more than
one logical IP subnet deployed on the same physical link … called shared networks in Kea" — and
offers the interface selector at shared-network level; "when the selected subnet is a member of a
shared network, the whole shared network is selected", and *there* the classes decide. ARM **8.4.2**
adds the part that makes a classless default subnet a defect rather than an omission: a subnet that
names no class accepts every client, and "a common mistake is to assume that a subnet that includes a
client class is preferred over subnets without client classes".

**The rule, and it generalises past Kea:** a behaviour question is answered by the section that
*defines* the behaviour, and reading it is cheaper than any number of experiments. Where a tool
validates its own input, read the whole verdict — warnings included — and count them; a filter that
keeps only `ERROR` throws away the tool telling you what is deprecated or ignored. And a measurement
that cannot distinguish the hypothesis from its alternative is not evidence for either: round 2 rested
on exactly such a measurement, and it was read as confirmation.

### 4.3 A service can own a system file - removing it silently takes the file with it

The Tailscale retirement took `hom-wrk-01` and then `mob-nb-01` offline, twice, for the same reason:
`tailscaled` owned `/etc/resolv.conf` (MagicDNS) and rewrote it on its own schedule. Removing the
service left the file behind, pointing at `100.100.100.100`, and with it every name lookup died. The
internet itself was fine - `ping 1.1.1.1` answered - which is exactly what made the symptom look like
something else.

What makes it a rule rather than an anecdote:

- **the replacement already existed and was already declared.** `my.topology.resolvers` feeds
  `networking.nameservers`, and the `static` feature sets it on every host with a static address. One
  query - `nix eval …config.networking.nameservers` - would have shown it before the first removal. The
  repository's own rule is *prove the replacement, then delete*; this was the delete step first.
- **ownership is not visible in the service name.** Nothing in `services.tailscale.enable` says
  "resolv.conf". The way to find out is to ask what writes the file (`ls -l` showed the owning group
  `resolvconf`) and who feeds it.
- **order is part of the change.** Deploying the hubs before the spokes is right for routing and wrong
  for ownership: the notebook stayed the last Tailscale node pointing at a resolver that the already-
  migrated hosts had been providing. When one service owns a resource for several hosts, the hosts that
  depend on it move **before** the ones that provide it.
- **a manual fix can be overwritten by the very writer you are working around.** `resolvconf -a` made
  no difference for seconds because `tailscaled` rewrote the file again; only stopping the writer worked.

### 4.4 Write the expectation down before you measure - it is the only way a measurement can disagree

The one error of that evening that a **check** caught rather than a user was the LAN route rule. The
deployment script printed the derived `allowedIPs` per host, I had written the expected line next to
it - "hom-wrk-01 -> no 10.10.10/20/30 (it is on the LAN)" - and the output said otherwise: a desktop
inside the LAN carried mesh routes for `infra` and `iot`.

Without that line the number would have looked plausible and shipped. Two smaller versions of the same
thing in the same session: a glob over `/nix/store/*tplink-ap*.json` that matched the *old and new*
rendered specs and reported both, and `wg show` with `stderr` discarded, whose empty output I first read
as "no peers" when it meant "no permission".

**The rule:** a measurement belongs next to the value it expects, so that a reader - or the next run -
can see a contradiction instead of a number. And when an instrument can fail silently, let it fail
loudly: keep `stderr`, check the exit code, and prefer the file the running unit actually reads over a
pattern that happens to match several.

## 4. One open investigation

### 5.0 `caddy reload` stalls: five hypotheses tested and refuted (2026-09-20, night)

**Symptom, measured.** `systemctl reload caddy` on `hom-srv-01` either failed fast (`exit 1`) or hung
exactly 90 s (`TimeoutStartSec`, which also governs reload jobs) and was killed as
`Reload operation timed out. Killing reload process.` The process stayed `active running`, kept
listening on 443 and answered **nothing** for any vhost, from the LAN and through the ingress. Only a
restart recovered it. Correlation: the host with 14 explicit `tls <file>` bindings hung; the ingress
with none never did.

**Reproduction built (isolated).** A scratch Caddy instance on ports 19119/19081/19443 with its own
certificates, a precondition that asserts admin API *and* data plane answer before any case runs, and
a data-plane probe that goes through TLS with SNI. Every hypothesis below was tested against it:

| Hypothesis | Experiment | Result |
|---|---|---|
| unreadable / truncated / mismatched certificate file makes the load hang | replace the bound file with a missing, truncated, and foreign-key variant | **refuted**: all three fail *fast* (`400`, `failed to find any PEM data`), data plane keeps answering 200 |
| a cert file rewritten *during* the load (the concurrent acme-unit situation) | writer replacing the file every 20 ms while reloading | **refuted**: reload 1 s, data plane 200 |
| in-flight requests hold the reload (eternal grace period) | upstream that never answers, verified established connection, real config change, with default and with `grace_period 5s` | **refuted**: reload returns in 0 s; Caddy drains the old server asynchronously (`grace period initiated` → `load complete` → `context canceled`) |
| concurrent reloads wedge the client | five simultaneous reloads, two with a broken config | **refuted**: all return in 0 s, data plane 200 |
| the module's `--force` reload on an unchanged config, with 14 bound sites (what the 14 acme units' `reloadServices` produce) | 14 concurrent forced reloads, unchanged config | **refuted**: 13 ok, 0 hung, 1 s wall time, data plane 200 |

**What the production log does show.** In the stall window Caddy logs the Caddyfile warnings, then
`adapted config to JSON`, then `stopping current admin endpoint` and
`shutting down admin server: stopping admin server: 10s timeout` — and nothing else. The load never
completed, the old servers were already stopped, so the service listened and answered nothing. The
load is triggered *through* the admin endpoint that Caddy tears down and rebuilds on every load, so
the stall sits in Caddy's own admin-endpoint teardown - not in certificates, not in connections, not
in concurrency.

**Root cause: not yet proven.** Every mechanism I could think of was falsifiable and got falsified, so
the next step is instrumentation, not another guess:

1. On the next stall, capture the blocked stack: the admin API exposes
   `GET /debug/pprof/goroutine?debug=1` (and `/debug/pprof/` generally). One request during a stall
   yields the exact goroutine that blocks the load. This is the decisive, low-cost measurement.
2. Enable `services.caddy.enableDebugLogs` so the next attempt logs its stages at debug level.
3. **Applied 2026-09-20, decided and verified:** `services.caddy.enableReload = false` on all three
   hosting hosts. The module then renders no reload command at all and uses `restartTriggers`, so a
   configuration change restarts Caddy. Verified on each host: activation `exit 0`, `caddy` active,
   zero reload commands in the unit, and `systemctl reload caddy` **refused** in under a second
   (`rc=3`, "Job type reload is not applicable") with the service still active afterwards - where it
   used to hang and take every vhost down. All public and internal names answered throughout.

   Not used: overriding `ExecReload`. `lib.mkForce` on that list does not displace the module's
   command, which survives in the rendered unit (measured), so the override was inert and was
   reverted rather than left as a claim.

**B1 — root access to `cld-edge-01`.** The edge trusts only the old fleet deploy key, whose private
half was destroyed when the openclaw tunnel rendered its secret over `~/.ssh/deploy-key`. Recovery
paths, in order of effort: (a) the old private key still exists somewhere (notebook, backup,
password manager); (b) the old SOPS hash is retrievable from git and candidate passwords can be
verified against it **without touching the VPS**; (c) the provider console — GRUB is unrestricted, so
`init=/bin/sh` then `passwd philipp`; (d) the provider's rescue system, then chroot and `passwd`.
The exact procedure, with the verified disk layout, is in `operations.md` §8.2.

**B2 — the deploy signal (A1).** Blocked on the one `cscli machines add` for `hom-srv-01` on the
master, which is also blocked on B1.

Both are the same blocker: without root on the edge, neither the fleet key nor the fleet-wide rollout
in A3 can be closed.

---

## 6. Directory work - twelve findings, each one measured late

Making Jellyfin authenticate against the Authentik directory took a night and produced six generalisable
findings. They are recorded because every one of them cost hours and none of them is specific to LDAP.

### 6.1 A blueprint is one atomic transaction - one invalid entry discards all of them

The upstream documentation states it plainly: *"When a blueprint is applied, all entries are processed within
a single atomic database transaction. If any entry fails validation, the entire blueprint is rolled back. No
partial changes."* A single invented value (`mode: implicit_consent` on a consent stage) therefore discarded
every entry of that blueprint, including the ones that were correct, and left the objects the previous apply
had created. Objects from an older, successful apply and objects from the current file can coexist; the file
is not a description of the database.

### 6.2 `status` is a statement about the blueprint, never about its entries

Four times this night the instance read `successful` while the object it should have created did not exist.
The cause is always the same: `last_applied` and `status` describe the last *attempt*, and a failed apply
leaves the previous value behind. The importer does name the failing entry - it logs
`Entry invalid: Serializer errors {...}` at warning level and it prints the entry, with its model and
attributes - but the log lines are JSON, and `grep -v '^{'` removes exactly the evidence. Read the object
(the row, the count, the model), and let the importer speak without filtering it.

### 6.3 Files in a read-only store cannot trigger the file watcher

The same page documents the two triggers: the blueprint directory is watched for modification events, and
every file is re-read hourly. Under Nix the directory is an immutable store path that a deploy replaces
wholesale, so no file inside it is ever *modified* and the watcher structurally cannot fire. The hourly tick
is the only automatic mechanism, which is why a change deployed at minute :29 takes effect at :27 of the next
hour. Two conclusions: never read a blueprint's status inside that window, and apply explicitly when a change
has to be live now (`apply_blueprint` is the task the discovery itself sends).

### 6.4 The LDAP provider's "Bind Flow" is the `authorization_flow` field

`providers/ldap/api.py` line 90: `bind_flow_slug = CharField(source="authorization_flow.slug")`. The outpost
reads `provider.BindFlowSlug` (`internal/outpost/ldap/refresh.go` line 67) and answers it with the
identification and password answers (`bind/direct/bind.go` lines 20-22), so the flow named there has to
authenticate. The provider's own `authentication_flow` field is a different thing. Setting the obvious field
leaves a bind broken in a way that looks like a credential problem.

### 6.5 A flow that runs before authentication must not carry bindings

A policy binding that names a specific user cannot match a request that arrives unauthenticated. With
`policy_engine_mode = any` and one failing binding the engine answers false - `any([False])` - and the flow
reports "Flow does not apply to current user". The same rule applies to the bind flow and to the application
access check. An unbound flow applies to everyone, and the audience belongs in the consumer's own filter.

### 6.6 An application bound to one account denies everyone else

The outpost calls the provider's `check_access` per user, which evaluates the *application's* policy engine;
a non-passing result becomes LDAP result 50, `Insufficient access rights`. Binding the LDAP application to
the service account alone therefore let the service account search and denied every human, with exactly the
same credentials: 49 for a wrong password, 50 for the right one. An application without any binding is open
to every user - `AppAccessWithoutBindings`, key `core_default_app_access`, default `True` - so the LDAP
application carries no binding and each consumer's `memberOf` filter decides who may sign in.

### 6.7 The rule underneath 6.4 to 6.6

**Read the consuming code, not the configuration it consumes.** Every wrong turn this night came from
trusting a field name (`authentication_flow`), a status (`successful`) or a plausible story ("the permission
must be missing"), and every correction came from opening the source that actually decides: the API
serializer, the Go outpost, the Django policy engine, the importer. The sources sit in the store
(`/nix/store/*-authentik-*/lib/python3.14/site-packages/authentik` and the outpost's Go tree), and the
documentation is available as a checkout, so none of this needs a hypothesis.

### 6.8 Removal is an entry, not an omission - and the first version of this file said otherwise

An earlier version of this section claimed blueprints cannot delete objects. That was wrong, and the
structure documentation says so in four lines:

```yaml
state: present       # creates if missing, updates the fields in attrs, leaves other fields alone
state: created       # creates if missing and never updates it again
state: must_created  # fails if it already exists
state: absent        # deletes it if it exists (Django .delete(), so it may cascade)
```

So a blueprint is declarative about the entries it **contains**; an object that merely disappears from the
file stays in the database. Removal has to be declared, as a tombstone that may stay there forever, because
`absent` on a missing object is a no-op. Deleting a flow cascades to its stage bindings, so one entry replaces
several.

### 6.9 Order across blueprints is declared, not retried

A deploy failed because two blueprints reference each other across files: the provider carries an object
permission for the consumer's role, and a different file creates that role. The task log named it exactly -
`KeyOf: failed to find entry with id of sa_ldap_consumer_jellyfin and a model instance` - while the file
itself was correct: the entry, the reference and a passing `validate()` were all there. The cause was the
sequence, and the second run of the same unit succeeded, which is the kind of "fix" that hides a defect.

The documentation is explicit twice over. Discovery and evaluation across files "is not guaranteed to follow
any specific order", and "if you have dependencies between blueprints, you should use meta models to make
sure that objects are created in the correct order". The meta model is
`authentik_blueprints.metaapplyblueprint`, and its identifiers are "key-value attributes used to match the
blueprint instance": the `path` of a file-based blueprint, or the `name` of a generated one. Both forms exist
here, and `required` defaults to true, so naming the wrong one fails the whole blueprint rather than the
dependency alone.

A retrying apply was written first and then removed. It worked, and that was the problem: a broken dependency
would have been papered over on the second pass instead of failing a deploy. Declaring the dependency costs
one entry, and the deploy is green in a single pass - which is now the measurement that says the declaration
is right.

### 6.10 The apply trigger, and how this repository closes it

Upstream re-reads a blueprint file every 60 minutes and watches the directory for modification events. In
this repository the directory is an immutable store path that a deploy replaces wholesale, so no file is ever
modified and the watcher cannot fire - measured as a deploy that changed blueprints, restarted the server and
the worker, and applied nothing until the next hourly discovery.

The fix uses the mechanism this repository already trusts for "act when the deployment changed":
`restartTriggers` content-hashes the blueprints directory into a unit, so systemd starts
`authentik-blueprints-apply` exactly when a deploy produced different blueprints - and on boot, where
authentik applies nothing by itself. The unit queues the same task the API's apply endpoint queues and then
waits for every instance to settle, asserting on `last_applied` being **newer** than before **and** on
`status`, because status alone describes the last attempt rather than this one. A deploy is therefore
finished when the objects exist, not when a file was written.

### 6.11 Depending on a fact we do not name is the quietest defect of all

Four times in one night the same shape appeared: something worked because the database happened to be in a
certain state, and nothing in the repository said so.

```
search_full_directory    set by hand in the database, needed by every consumer    (now declared)
token.managed            undeclared - authentik could claim the token              (now declared)
token.expiring           `true`, so authentik rotated the outpost key every        (now declared)
                         30 minutes - measured as `secret_rotate` events
provider.mfa_support     `true` in the database, undeclared                      (now declared)
brand.branding_logo      a file that has to exist, referenced by name only         (documented)
```

All four are invisible: the system works, every check passes, and the defect only appears on a fresh install,
a restore, or the day authentik rotates something. The rule that follows is not "the repository must contain
everything" - that claim is what produces declarations that fight their users - but: **every fact we depend on
is either declared, or documented with the reason it cannot be.** A silent dependency on the database is a
defect, not a convention.

The same case also shows why the field named in a bug report is not always the field that causes it.
`token.managed` is a text marker - a non-empty string means authentik owns the object - and the serializer
accepts only a non-empty string or SQL NULL: `managed = false` (the Nix boolean) is rejected as "not a valid
string", which is what made every apply of the outposts blueprint fail on 2026-09-20, and `""` is rejected as
blank. The declaration is `managed = null`. But the rotation that actually blinded the outposts is driven by a
different field: `Token.expire_action` rotates **every** api-intent token whose `expires` has passed,
regardless of `managed` - measured as `secret_rotate` events for both outpost tokens every 30 minutes, while
the outpost had read its key once at start. `expiring = false` is what stops it (an app_password expires
instead of rotating, which breaks a bind at the same interval). Both facts are declared, and the apply asserts
them for every token whose key comes from SOPS.

The same night produced the mirror image, and it is worth naming both together: a fact the declaration *does*
mention, which a person then changes in the interface. It is not a deviation, it is a revert with a deadline -
`present` overwrites the declared fields at the next apply. The answer is to report it, not to forbid it, and
to keep the declarations to the things that are topology, policy or integration (see
[`identity.md` §11](./identity.md)).

### 6.12 A rename is a new entry plus a tombstone

Access hangs on group names through every consumer's `memberOf` filter, so a name is part of the shape of the
system, not a label. Renaming a group in the interface removes everyone's access and turns nothing red;
renaming it here by editing the `identifiers` in place leaves the old object behind, and the old name still
grants access. The discipline is one entry with the new name **and** one `state: absent` entry for the old
one - the tombstone is the only thing that makes the rename declarative, and it may stay forever because
`absent` on a missing object is a no-op. The apply checks the rule in both directions: every declared object
resolves (`present`) and every tombstoned identifier is gone (`absent`).


