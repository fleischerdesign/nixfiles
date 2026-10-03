# 0007 - Ownership labels and admission

- **Status:** accepted
- **Date:** 2026-10-03

## Context

Several domains carry both declared and observed truth, often on the same object. Without an explicit
notion of who owns which field, two writers silently overwrite each other, and the resulting flapping
is exactly the mishmash the model exists to prevent (**R3**, **R4**, **E9**).

## Decision

Every reconciled object carries exactly one ownership label - `owner=declared`, `owner=observed` or
`owner=derived` - and admission enforces the rule: a writer may not modify a field it does not own.
Conflicts are rejected at admission, never resolved silently.

## Consequences

- The engine can be told, mechanically, which fields to enforce and which to leave.
- A second writer becomes a rejected request with an actor, not a race.
- Objects with genuinely shared fields are split into two fields until each has one owner.
- Admission is now load-bearing: it must be tested (a write from the wrong owner must fail loudly).

## Alternatives

- **Per-object ownership** - too coarse; a single `Gateway` legitimately mixes declared and observed
  fields.
- **Last-writer-wins** - the failure mode itself; rejected.
- **Convention without enforcement** - a rule that cannot fail is not a rule
  ([`../../../AGENTS.md`](../../../AGENTS.md), non-negotiable 2).
