# QUALITY.md — the engineering bar, and what still stands in its way

`ARCHITECTURE.md`, `NAMING.md` and `IDENTITY.md` describe **what** this configuration is.
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

## 3. Measured state (2026-09-20, after the 2.0 refactor pass)

| Criterion | Measurement |
|---|---|
| **A1** | **resolved and measured**: `--failed` is `0` on all five hosts and `nixos-rebuild switch` returns `exit 0` on every one of them. The last failure was the CrowdSec agent (renamed host → `ent: machine not found`), registered on the master. The `2` failed units seen on the edge after the rescue were transient state, not defects, and cleared on their own |
| **A2** | **10 of 12 resolved** in `58f4139` (+17/−69): searxng (the reference case), the nine live options, and the dead `couchdb` option deleted outright. Every consumer now reads its contract's `canonicalDomain` — which is derived plane-aware, so the option that could only ever express the public plane is gone. **2 remain, both verified as correct rather than pending**: `mail` (SMTP hostname and certificate copy — legitimately independent) and `openclaw/gateway`'s per-instance `domain`, which turned out to be a *contract parameter* (the base domain the endpoint builds its name from, set by `cld-ops-01` for all five instances) and not a second derivation — the construct is right where it is |
| **A3** | **resolved for all five hosts**: `hom-srv-01` (already current; the no-op deploy proved it), `cld-ops-01`, `cld-edge-01` (rebuilt and activated after the rescue) and `hom-wrk-01`; `mob-nb-01` followed once it was online — it was on an old generation without fleet access, so the closure was built locally and pushed with `nix copy` (the target's daemon imports as root), then activated detached through a `sudo` from `philipp`. It came back as `mob-nb-01` on the current revision with 0 failed units, `sshd` listening only on its overlay address, and its WireGuard up |
| **A4** | I11 reports four hosts: `hom-ap-01: 192.168.178.54/24`, `hom-rt-01: 192.168.178.1/24`, `hom-srv-01: 192.168.178.27/24`, `hom-wrk-01: 192.168.178.30/24`. **Deliberately deferred**: these blocks are the fallback that still works while the new subnet settles, and the migration guard is armed exactly as long as they exist. Removing them is the last step of the cutover, not an early one |
| **A5** | **resolved and applied**: `--prune` existed, was documented as deleting records, and `args.prune` was read nowhere — the reconciler was additive only and could never remove the labels it had created itself. Pruning is now ownership-scoped (the desired-set check is primary, the comment vocabulary answers "did we write this?"), and the unit passes it, so the zone is a function of the configuration. First real run: `0 created, 0 updated, 35 unchanged, 3 stale, 3 deleted` — `edge.`, `ops.` and `salus.vyrx.de` are gone. Records the engine does not own are unreachable by construction, which is why `srv.lan.vyrx.de` (written by `cloudflare-dyndns`) survived; see §13 item 17 |
| **A6** | **resolved**. Root access was restored through the provider's rescue system after my own gateway precedence change had left the edge with no default route; the edge now boots the corrected generation by default, and every server trusts both the operator key and the fleet key (`~/.ssh/nixfiles-deploy-key`, `SHA256:EduFlyo…`). `~/.ssh/config`, `nod`'s `identityFile` and `deploy-rs`'s `-i` argument all use the fleet key; `~/.ssh/deploy-key` points at the node tunnel secret and is documented as not for fleet access. The LAN certificate failure is resolved by the per-name DNS-01 model, measured from inside the LAN: `jellyfin` 302, `mealie` 200, `hass` 200, `seerr` 307, each with a Let's Encrypt issuer where there used to be a handshake failure |
| **A6 (passwords)** | `users.philipp.password` was **always** the hash of `173695` — verified against the value in git history with `perl -e 'print crypt(…)'`. The drift was never in the declaration but in its enforcement: `mutableUsers = true` applied it only at account creation, so `cld-edge-01` kept whatever the provider's install set, and the panel's password reset never reached the OS (it works through cloud-init on the provider's own images; this is NixOS). Servers now set `users.mutableUsers = false`, so the declaration is applied on every activation — and this is now **measured**, not assumed: the `hom-wrk-01` activation printed `modifying secret: users/philipp/password`, and a non-interactive `sudo -S` with `173695` succeeds |

| **Zones (LAN)** | **mechanism resolved and proven; one device is still on a pre-change lease.** All three zones live in **one** Kea shared network, each subnet bound to one client class - `infra`, `iot`, and the complement `corp` for whatever the inventory does not declare - because Kea's default subnet selection for a directly connected client uses the *receiving interface's address* and ignores classification entirely (ARM 8.6, see §4.2). Proof: all six iot relays were flashed over OTA, re-requested DHCP, and came back on the addresses their inventory entries declare (`hom-rly-01` … `hom-rly-08` → `10.10.30.11/.12/.13/.16/.17/.18`, each confirmed by `DHCP4_LEASE_ALLOC` and a `REACHABLE` neighbour entry). **Also moved:** `hom-ap-01`, after a reboot through the same library the tplink-ap engine uses (`TplinkRE330Router.reboot()`; the engine itself exposes no reboot action) — it came back on its declared `10.10.10.20` and stopped answering on `10.10.20.100`. A software reboot alone does *not* do it: measured, no DHCP packet from its MAC appeared in Kea's log while it kept its stored 24 h lease. And `hom-prn-01`, the scanner, is declared with its MAC and leases `10.10.30.19` from the iot zone; until the MAC was declared it sat on a corp pool lease, which is the rule rather than a fallback. Every device in the inventory is therefore in the zone its entry names |

**Holding:** invariants I1–I10 assert clean (0 errors under `flake check`); the compatibility shim is
gone (0 occurrences); the `vlan` field is gone (0 occurrences).

---

## 4. The method that works here — and the two times it was ignored

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

## 5. Open blockers — and one open investigation

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
The exact procedure, with the verified disk layout, is in `DEPLOYMENT.md` §11.2.

**B2 — the deploy signal (A1).** Blocked on the one `cscli machines add` for `hom-srv-01` on the
master, which is also blocked on B1.

Both are the same blocker: without root on the edge, neither the fleet key nor the fleet-wide rollout
in A3 can be closed.

---

## 6. The rename problem — six registries, one cause

Renaming the hosts (`strummer` → `hom-srv-01`, `jello` → `hom-wrk-01`, `mackaye` → `cld-edge-01`,
`rollins` → `cld-ops-01`, `yorke` → `mob-nb-01`) was treated as a configuration change. It was a
state migration, and every system that keys on the hostname had to be migrated with it. The ones we
stumbled over on 2026-09-19, in the order they bit:

| # | Registry | Symptom | State |
|---|---|---|---|
| 1 | `sshd` `listenAddresses` | the migration address was never bound → deploy locked itself out of the host | fixed |
| 2 | Chrome `SingletonLock` (contains `<hostname>-<pid>`) | "profile in use on another computer" and no way to start Chrome | fixed (stale lock removed) |
| 3 | CrowdSec machine registry | the agent authenticates as `<hostname>`, so the rename made it a stranger: `ent: machine not found` | **resolved, and it was a latent defect rather than debt.** `hom-srv-01` had been registered first, but the ops agent still authenticated as `rollins`: its process had been running since before the rename, so it kept working with the old credentials file in memory while the *rendered* file already said `cld-ops-01`. It would therefore have gone blind at its next restart, and `active` would not have shown it. The registry held the proof - `rollins` heartbeating while `cld-ops-01` had no heartbeat. Both current identities were registered and their heartbeats **verified before anything was deleted**; then `rollins`, `strummer`, `jello`, `yorke` were removed. `mackaye` stays - it is the master's own entry. All three hosts: crowdsec active, bouncer active, 0 failed |
| 4 | per-host `domain` fields | a second naming scheme that the rename made visibly wrong (`srv.lan.vyrx.de` for `hom-srv-01`) | fixed (fields deleted) |
| 5 | Caddy access-log filenames (`access-<vhost>.log`) | stale files, and the agent could not read them (`permission denied`) → the IPS ran but was blind to HTTP | **fixed and verified**: `z /var/log/caddy/*.log 0640 caddy caddy` plus `crowdsec` ∈ `caddy`; `cscli metrics` shows every `access-<vhost>.log` read and parsed. My later "still not readable" check tested an invented filename (`access.log`) — see §4.1 |
| 6 | host-keyed state in user profiles (`dconf`, VS Code, kdeconnect, session stores) | harmless strings, no action | accepted |

**The rule this yields:** a hostname change is finished only when every registry keyed on the hostname
has been migrated — and since we found six by accident, the list is probably incomplete. The systemic
conclusion is not a longer checklist but a narrower habit: **treat a fleet-wide rename as a migration
with a verification phase, like the subnet cutover — or do not rename at all.**

The concrete open item #5 from this table is closed. What remains here is not a defect but inert debt:
the stale entries in the CrowdSec machine registry (#3), harmless as long as nobody mistakes them for
live machines — `mackaye` is the master's own entry and must not be deleted.
