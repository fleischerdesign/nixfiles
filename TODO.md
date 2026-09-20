# Work list — authentik, to the end

**This is a work list, not a specification.** It describes what is still missing and how each item is
accepted; it must be deleted or emptied as the items are done. What the system *is* lives in
[`docs/identity.md`](docs/identity.md) and [`docs/practices.md`](docs/practices.md); a document in `docs/`
that describes planned work would be a lie two weeks from now, which is why this file sits at the root.

## The acceptance criterion of all of it

> A fresh database plus one deploy produces exactly the declared world — and never touches the six
> people-owned things from the ownership rule in `docs/identity.md` §11.

Everything below serves that sentence.

## Rules being implemented

    R1  Nix owns the shape of the system (topology, policy, integration). The interface owns the people.
    R2  A fact has exactly one owner — never two, never "first us, then them".
    R3  Every relationship we set is checked: may a human change it? Yes exactly when we do not declare it.
    R4  What we depend on but do not set is declared, or documented with a reason — never silent.

## Evidence collected so far (so the next agent does not rediscover it)

| # | Fact | Where measured |
|---|---|---|
| E1 | The apply unit applies **all** enabled instances, including authentik's own defaults | `features/services/authentik/server/default.nix`, in the apply script: `BlueprintInstance.objects.filter(enabled=True)` |
| E2 | A UI change to a declared field is silently reverted by the next apply (`present` overwrites `attrs`) | blueprint structure documentation |
| E3 | `state: absent` deletes; `state: created` creates once and never updates afterwards | same documentation |
| E4 | Order across blueprint files is not guaranteed; dependencies go through `metaapplyblueprint` | blueprint index page |
| E5 | `metadata.labels` exist; the apply task copies them to `instance.metadata` | structure docs + upstream `authentik/blueprints/v1/tasks.py` |
| E6 | Our tokens have `managed = ''`, authentik's own have `goauthentik.io/outpost/…` — and `managed` appears nowhere in Nix | `authentik_core_token`, `grep managed` |
| E7 | `provider.mfa_support` is `true` in the database and cannot be set through the blueprint (the apply fails) | earlier attempt, recorded in commit history |
| E8 | The five seeded users declare `groups:` — a relationship humans must be able to change | `features/services/authentik/server/blueprints/01-rbac/users-and-groups.yaml`, the five `- model: authentik_core.user` entries |
| E9 | Groups declare **no** member list (`users:` occurs 0×) — correct, and must stay that way | same file |
| E10 | The blueprint JSON schema has `additionalProperties` 32× but `false` 0× — it cannot catch an unknown field name | `https://goauthentik.io/blueprints/schema.json` |
| E11 | `features/services/authentik/server/blueprints/02-flows/recovery.yaml`, the line with `from_address:` sends mail from `noreply@ancoris.ovh` (old domain) | `grep ancoris` |
| E12 | `DC=vyrx,DC=de` is a literal in `contracts/directory`, not derived from `my.topology.domain` | `contracts/directory/default.nix`, the line with `lib.mkDefault "DC=vyrx,DC=de"` |
| E13 | The `consentStage` builder and its model entry are unused since the authorization-flow experiment was removed | `features/services/authentik/lib/blueprint.nix` |
| E14 | `akadmin`'s password exists only as a hash in SOPS — no human can sign in as it | `AUTHENTIK_BOOTSTRAP_PASSWORD_HASH` |

## Work packages

### P1 — Scope the apply to our own blueprints  (highest priority; prevents data loss)

**Evidence**: E1. A UI change to authentik's own default flows is discarded by every deploy, silently.
**What**: mark our generated and hand-written blueprints with `metadata.labels.vyrx = "owned"` (E5) and send
only instances carrying that label from the apply script.
**Acceptance**: the unit's log lists only `vyrx-*` instances; all of them end `successful`.
**Check**: grep the unit log for the applied instance names; compare the instance list before and after.
**Risk / rollback**: a forgotten label means an instance is no longer applied — visible through the
invariants. Rollback is removing one label.

### P2 — Declare `token.managed = false`

**Evidence**: E6. Today's unmanaged tokens are an accident of the database; a fresh install creates managed
tokens, authentik rotates them, the outpost goes blind — the outage of 2026-09-20.
**What**: set `managed = false` in the `token` builder. Add an invariant "outpost tokens are unmanaged" (P4).
**Acceptance**: `select identifier, length(managed) from authentik_core_token` returns 0 for our tokens, and
a freshly created token in a test database is unmanaged too.
**Check**: the query above before and after a deploy.

### P3 — Inventory undeclared dependencies and close them

**Evidence**: E7 and the three further cases: `provider.bind_mode`/`search_mode` (DB `direct`, origin
unknown), `brand.branding_logo`/`theme.css` (files that must exist), the flag behind
`AppAccessWithoutBindings` (default true — we depend on it).
**What**: for every model we declare, list the fields we **rely on but do not set**, and for each either
declare it or document it as not settable with the evidence. `mfa_support` is the known not-settable case.
**Acceptance**: every row of that list is either set in a blueprint or documented in `docs/identity.md` with
a reason and a citation. No row reads "unknown".

### P4 — Invariants: from a sample to a derivation

**Evidence**: seven hand-written `expect()` calls (`features/services/authentik/server/default.nix`, the `def expect(` calls in the apply script) guard exactly the two
failures of that night.
**What**, three levels:
- **existential**: every non-`absent` entry of every one of our instances resolves to an object — the
  importer already parses `model` + `identifiers`, the same source the apply uses.
- **cardinal**: for every relationship set we own, "exactly N": stage bindings of our flow (3), policy
  bindings on the `ldap` application (0), providers of each outpost (1), role permissions, provider flows.
- **directional**: capabilities that depend on a database fact: tokens unmanaged (P2),
  `search_full_directory` for each consumer account.
**Acceptance**: a deliberately broken expectation turns the deploy **red** — already demonstrated once, at the
401 incident.
**Check**: one negative test per invariant, then revert it.

### P5 — Remove relationships that humans own

**Evidence**: E8 (five seeded users declare `groups`), E9 (groups correctly declare none).
**What**: drop `groups:` from the seeded users — the object is seeded, the relationship is not. Document that
access runs **only** through membership: no per-user application bindings, because two mechanisms are two
truths.
**Acceptance**: adding a user to `family` in the interface survives a deploy; removing one from `media-users`
stays removed.
**Check**: deploy, perform both actions in the interface, deploy again, compare memberships.

### P6 — Names are part of the system's shape (rename discipline)

**Evidence**: access hangs on group names through `memberOf` filters (Jellyfin, and every future consumer).
A rename in the interface removes access for everyone without anything turning red; a rename in Nix leaves an
orphan that can still grant access.
**What**: the rule in `docs/practices.md` — renaming means a new entry **plus** `state: absent` for the old
one — and an invariant that forbidden old names are gone.
**Acceptance**: a rename test on an object with no use (a test role) leaves only the new name after a deploy.

### P7 — Drift report (report only, never correct)

**Evidence**: we detect no drift today, and the unit only runs when blueprints change — precisely not when a
human works in the interface and nobody deploys.
**What**, two arms, on a timer (`OnCalendar`) in addition to `restartTriggers`:
- **declared vs actual**: the fields in `attrs` against the objects → "this will be reset at the next apply",
  the warning that is missing today;
- **authentik events** (`model_updated` with the acting user) → also covers undeclared objects and fields,
  and answers "who changed what, when".
**Acceptance**: changing a test object in the interface makes the report name object, field, user and
consequence — and changes nothing (empty diff before and after).

### P8 — Remaining gaps

- **a** `DC=vyrx,DC=de` (E12) → derive from `my.topology.domain`.
- **b** `noreply@ancoris.ovh` (E11) → the current domain, derived if possible; it is the last `ancoris` trace
  in the authentik part and it is user-visible, because it sits in the recovery flow.
- **c** the unused `consentStage` builder and its model entry (E13) → remove. `deadnix` does not see unused
  attribute-set fields.
- **d** `akadmin` (E14) → decide and write it down: either a documented break-glass account with a rotated
  password in SOPS, or explicitly documented as not sign-in-able. Admin access runs through membership in
  `infra-admins` (`is_superuser`), and a new admin must be able to find that in one sentence.

### P9 — The rules and the table into the documentation

**What**: `docs/identity.md` §11 carries the per-model table (owner, relationships we set, "may a human
change it?") and the UI-DARF/UI-NICHT lists verbatim. `docs/practices.md` carries the rename rule (P6) and the
sentence "dependencies between blueprint files are declared with `metaapplyblueprint`, not retried" (already
in §6.9).
**Acceptance**: a stranger finds the answer to "may I change X in the interface?" in under a minute.

### P10 — The final acceptance test

**What**: a fresh database plus one deploy ⇒ the declared world exists, all invariants hold, the login works.
**How, without production risk**: a throwaway instance — a second database (`AUTHENTIK_POSTGRESQL__NAME`) or
a container with the same blueprints; applying needs only PostgreSQL and Redis.
**Acceptance**: `applied and verified`, login 200, `managed = ''`, `mfa_support` untouched, and the four
interface cases from P5 behave as stated.
**Why it is worth it**: it is the only test that definitively excludes the class "works today because the
database happens to be like this" — the class that appeared four times on 2026-09-20.

## Order

    P1  apply scope            immediately — prevents losing an admin's work, and P5 is unmeasurable without it
    P2  managed = false        immediately — availability, small
    P5  remove relationships   after P1 — otherwise foreign instances distort the measurement
    P8a/b  domain + ancoris    alongside — one line each
    P4  derived invariants     after P2/P5, so they check the new state
    P3  dependency inventory   parallel — diligence work
    P7  drift report           after P4 — uses the same ownership set
    P8c/d  dead builder, akadmin   any time
    P9  documentation          continuous, consolidated at the end
    P10 final acceptance       last

## Risks this list does not close (deliberately)

1. **Direct SQL changes** stay invisible — no event, no blueprint. The only countermeasure is the rule "the
   database is not a change path" plus the event arm of the report.
2. **Fields authentik refuses to declare** (`mfa_support`) remain a dependency: impossible to declare,
   therefore documented and checked.
3. **Objects nobody declares** (created in the interface) are not reclaimed — intended.
4. **A new consumer needs a SOPS secret by hand.** It stays manual; the deploy fails loudly, and the step
   "add a consumer" is documented.

## One addition for whoever executes this

Four of the failures of 2026-09-20 came from trusting a *name* (`authentication_flow`),
a *status* (`successful`), a *plausible story* ("the permission must be missing") or an *incomplete read*
(`grep -c` counting lines in a one-line file). Every correction came from opening the source that actually
decides — the API serializer, the Go outpost, the Django policy engine, the importer, the JSON schema. The
sources are in the store and the documentation is checked out at `/tmp/authentik-docs` (a checkout of goauthentik/authentik, `website/docs/`); nothing here needs a
hypothesis.
