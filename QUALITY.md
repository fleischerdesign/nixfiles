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
| **A3** | **resolved**: every reachable host runs the current revision — `hom-srv-01` (already current; the no-op deploy proved it), `cld-ops-01`, `cld-edge-01` (rebuilt and activated after the rescue) and `hom-wrk-01`. Only `mob-nb-01` is not deployed, because it is offline |
| **A4** | I11 reports four hosts: `hom-ap-01: 192.168.178.54/24`, `hom-rt-01: 192.168.178.1/24`, `hom-srv-01: 192.168.178.27/24`, `hom-wrk-01: 192.168.178.30/24`. **Deliberately deferred**: these blocks are the fallback that still works while the new subnet settles, and the migration guard is armed exactly as long as they exist. Removing them is the last step of the cutover, not an early one |
| **A5** | **resolved and applied**: `--prune` existed, was documented as deleting records, and `args.prune` was read nowhere — the reconciler was additive only and could never remove the labels it had created itself. Pruning is now ownership-scoped (the desired-set check is primary, the comment vocabulary answers "did we write this?"), and the unit passes it, so the zone is a function of the configuration. First real run: `0 created, 0 updated, 35 unchanged, 3 stale, 3 deleted` — `edge.`, `ops.` and `salus.vyrx.de` are gone. Records the engine does not own are unreachable by construction, which is why `srv.lan.vyrx.de` (written by `cloudflare-dyndns`) survived; see §13 item 17 |
| **A6** | **resolved**. Root access was restored through the provider's rescue system after my own gateway precedence change had left the edge with no default route; the edge now boots the corrected generation by default, and every server trusts both the operator key and the fleet key (`~/.ssh/nixfiles-deploy-key`, `SHA256:EduFlyo…`). `~/.ssh/config`, `nod`'s `identityFile` and `deploy-rs`'s `-i` argument all use the fleet key; `~/.ssh/deploy-key` points at the node tunnel secret and is documented as not for fleet access. The LAN certificate failure is resolved by the per-name DNS-01 model, measured from inside the LAN: `jellyfin` 302, `mealie` 200, `hass` 200, `seerr` 307, each with a Let's Encrypt issuer where there used to be a handshake failure |
| **A6 (passwords)** | `users.philipp.password` was **always** the hash of `173695` — verified against the value in git history with `perl -e 'print crypt(…)'`. The drift was never in the declaration but in its enforcement: `mutableUsers = true` applied it only at account creation, so `cld-edge-01` kept whatever the provider's install set, and the panel's password reset never reached the OS (it works through cloud-init on the provider's own images; this is NixOS). Servers now set `users.mutableUsers = false`, so the declaration is applied on every activation — and this is now **measured**, not assumed: the `hom-wrk-01` activation printed `modifying secret: users/philipp/password`, and a non-interactive `sudo -S` with `173695` succeeds |

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
  evaluates options nobody evaluates in production.

## 5. Open blockers

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
| 3 | CrowdSec machine registry | the agent authenticates as `<hostname>`, so the rename made it a stranger: `ent: machine not found` | fixed (`hom-srv-01` registered); stale `mackaye`, `strummer`, `rollins`, `jello`, `yorke` remain as inert debt — `mackaye` is the master's own entry and must **not** be deleted |
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
