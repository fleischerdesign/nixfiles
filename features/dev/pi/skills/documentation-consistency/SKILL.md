---
name: documentation-consistency
description: Pre-merge gate that keeps living documentation (architecture overview, ADRs, specifications) in sync with code. Use after code review for changes touching architecture, interfaces, or behavior. Produces a doc-consistency verdict.
---

# Documentation Consistency

Documentation that drifts from code is worse than no documentation — it is confidently wrong. The constitution promises a living architecture overview, ADRs as the permanent decision record, and co-located specifications. This skill enforces that promise: it checks whether the documents that SHOULD have changed actually DID.

## Theoretical Foundation

- **Living Documentation** (Martraire 2019): Documentation that is continuously validated against the system it describes. A living document fails when it drifts; the failure is detectable and this skill is the detector.
- **Traceability** (your Engineering Constitution): code traces to tests, tests to specifications, specifications to requirements. A broken link anywhere in this chain is a defect before it is code.
- **Architecture Decision Records** (Nygard 2011): Decisions are recorded when made — not retroactively. ADRs are superseded, never deleted or renumbered.
- **Documentation Decay**: Unchecked documentation rots fastest at exactly the points where it matters most — architecture and interfaces — because those are where code changes most often and docs are updated least often.

## Trigger

Load this skill when:
- `code-review` has produced (or is about to produce) an APPROVE verdict
- The change touches architecture, module boundaries, public interfaces, or user-visible behavior
- This is the final pre-merge gate

Do NOT load this skill for:
- Trivial changes (typo, formatting, single-line with no surface change)
- Pure internal implementation details with no external contract

## Process

### Step 1: Doc-Impact Assessment

Classify the change:

```
Does the change alter any of:
- [ ] Architecture (component map, data flow, module boundaries)
- [ ] Public interfaces (APIs, CLI, config schema, wire format)
- [ ] User-visible behavior (features, edge cases, error messages)
- [ ] Operational surface (runbooks, deployment, monitoring)
- [ ] Onboarding material (getting-started, dependencies)

If NONE are affected: record "no doc impact" and exit. This is the fast path.
If ANY are affected: proceed to Step 2.
```

### Step 2: Inventory the Doc Graph

```
1. docs/architecture/overview.md — living system overview
2. docs/adr/ — decision records (and their index if one exists)
3. <feature>.spec.md — co-located specifications
4. README / CONTRIBUTING — onboarding and contribution rules
5. Runbooks / operational docs — deploy, incident response

For each, determine: does THIS change make any of these stale?
```

### Step 3: Staleness Check

For each document the change touches, ask:

```
- overview.md: are the component map, data flow, and key decisions still accurate?
- ADRs: does this change represent a NEW architectural decision that must be
  recorded? Does it SUPERSEDE an existing ADR (new ADR referencing the old)?
- specs: do the acceptance criteria still describe the actual behavior?
- README/runbooks: are setup steps, commands, or procedures still correct?
```

### Step 4: Enforce — Update or Justify

```
For every stale document, exactly one of:
1. Update it in the same change (preferred — the change and its docs ship together)
2. Record an explicit "no doc change needed" with rationale (acceptable only when
   the staleness is pre-existing and out of scope — file a follow-up)

New architectural decisions REQUIRE an ADR — do not fold a significant
decision into a code comment. If the decision is major, hand off to
`architecture-design` to write the ADR properly.
```

### Step 5: Verdict

Produce a verdict mirroring `code-review`:

```markdown
## Documentation Consistency

**Verdict:** APPROVE | REQUEST CHANGES

### Stale documents
- [doc path] — [what is stale, what should change]

### No-op justifications
- [doc path] — [why no change is needed]

### New decisions requiring ADRs
- [decision] — [ADR written or handoff to architecture-design]
```

## Evidence

After completing this skill:
- [ ] Doc-impact assessment recorded
- [ ] Doc graph inventoried
- [ ] Staleness findings per document
- [ ] Updates made OR no-op justified with rationale
- [ ] Verdict produced

## Exit Gate

Documentation consistency is complete when:
- Every stale document is either updated or has an explicit, justified no-op
- Any new architectural decision has an ADR (or a handoff to write one)
- The verdict is clear and unambiguous

## Handoff

After this skill:
- **`release-management`** — if this change ships as a versioned release
- **`integration-deployment`** — if deployment follows directly
- **`code-review`** — if the doc check revealed a design problem that needs re-review

## Anti-Patterns

- **"We'll update the docs later"**: The most common form of documentation debt. If the docs aren't updated in the same change, they will not be updated.
- **Retroactive ADRs**: Writing an ADR after merge to justify what was built. ADRs capture the decision process, not the outcome.
- **Doc-only churn**: Rewriting prose without a corresponding code change, or "improving" docs that weren't made stale. Documentation is minimal and purposeful.
- **Over-documenting trivial changes**: Requiring an overview.md update for a typo fix. The fast path exists for a reason.
- **Treating README as architecture**: The architecture overview is the system record. A README edit does not substitute for an overview.md or ADR update.
