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

## 3. Measured state (end of session 2026-09-19)

| Criterion | Measurement |
|---|---|
| **A1** | `--failed`: `hom-srv-01` **1** (crowdsec agent), `cld-ops-01` 0, `cld-edge-01` 0 → the server still ends every activation with `exit 4` |
| **A2** | **12** feature `domain` options remain (1 of 12 done: searxng). Two are additionally **dead**: `couchdb` (0 uses), `openclaw/gateway` (0 uses). `mail` (9 uses) is legitimately independent |
| **A3** | repository produces `hom-srv-01: d814rq87…`, `cld-ops-01: g38bkg17…`, `cld-edge-01: 6bsq65pz…` — `cld-ops-01` and `cld-edge-01` run older revisions |
| **A4** | I11 reports four hosts: `hom-ap-01: 192.168.178.54/24`, `hom-rt-01: 192.168.178.1/24`, `hom-srv-01: 192.168.178.27/24`, `hom-wrk-01: 192.168.178.30/24` |
| **A5** | `edge.vyrx.de` and `ops.vyrx.de` still answer `Status: 0` (they exist) while their source of truth in the repository is deleted |
| **A6** | root trust: `hom-srv-01` → operator key (deployed) · `cld-ops-01` → tunnel key + old fleet key · `cld-edge-01` → **only** the old fleet key, whose private half was destroyed → root access to the edge is currently impossible without a console. `~/.ssh/config` offers the whole fleet `~/.ssh/deploy-key`, which today is the **tunnel** credential. The home Caddy cannot obtain certificates for names that resolve to the edge, so `jellyfin.vyrx.de` fails from inside the LAN |
| **A6 (passwords)** | `users.philipp.password` was **always** the hash of `173695` — verified against the value in git history with `perl -e 'print crypt(…)'`. The drift was never in the declaration but in its enforcement: `mutableUsers = true` applied it only at account creation, so `cld-edge-01` kept whatever the provider's install set, and the panel's password reset never reached the OS (it works through cloud-init on the provider's own images; this is NixOS). Servers now set `users.mutableUsers = false`, so the declaration is applied on every activation |

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
| 5 | Caddy access-log filenames (`access-<hostname>.log`) | stale files, and the agent cannot read them (`permission denied`) → the IPS runs but is blind to HTTP | open |
| 6 | host-keyed state in user profiles (`dconf`, VS Code, kdeconnect, session stores) | harmless strings, no action | accepted |

**The rule this yields:** a hostname change is finished only when every registry keyed on the hostname
has been migrated — and since we found six by accident, the list is probably incomplete. The systemic
conclusion is not a longer checklist but a narrower habit: **treat a fleet-wide rename as a migration
with a verification phase, like the subnet cutover — or do not rename at all.**

The concrete open item from this table is #5: `crowdsec` cannot read `/var/log/caddy/*.log`. A service
that is `active` but blind to its main input is the same failure class as `exit 4` being normal:
the status says nothing about the effect.
