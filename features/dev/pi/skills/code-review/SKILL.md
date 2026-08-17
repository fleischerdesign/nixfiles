---
name: code-review
description: Pre-commit quality gate. Systematically review code for correctness, cognitive load, DRY violations, naming quality, error handling completeness, and architectural consistency. Use before committing, merging, or submitting for human review. Produces a structured review summary with findings organized by severity.
---

# Code Review

Code review is not a rubber stamp. It is the final quality gate before code enters the shared repository. You review as if you will be personally responsible for maintaining every line you approve.

## Theoretical Foundation

- **Cognitive Load Theory** (Hermans 2021, Sweller 1988): Code has three types of cognitive load. Intrinsic (inherent to the problem), extraneous (caused by how the code is written), and germane (effort spent building understanding). Minimize extraneous load; optimize for germane load.
- **DRY Principle** (Hunt & Thomas 1999): Every piece of knowledge must have a single, unambiguous, authoritative representation. DRY is about knowledge duplication, not textual duplication. Two pieces of code that look identical but represent different knowledge are not a DRY violation.
- **Least Power Principle** (Berners-Lee 2006): Use the least powerful construct that solves the problem. A function is better than a class; a value is better than a function; a standard library call is better than custom code.
- **Chekhov's Gun**: Every element in the code must be necessary. If a parameter, variable, or branch exists, it must be exercised and justified. Remove anything that isn't.
- **Normalization of Deviance** (Vaughan 1996): Small violations of standards, when accepted repeatedly, become the new standard. Review must catch the first instance.

## Trigger

Load this skill when:
- A change is ready to commit, merge, or submit for human review
- The user explicitly asks for a code review
- `tdd-discipline` handoff signals implementation is complete
- You are about to suggest a commit message

Do NOT load this skill:
- During active implementation (review is a separate phase)
- For work-in-progress that hasn't passed TDD gates

## Subagent Delegation

For any non-trivial change, dispatch a `review` subagent with fresh context for an independent, unbiased review:

```
task({
  subagent_type: "review",
  prompt: "Review [branch/commit/diff]. Specification: [spec reference]. Key architectural decisions: [ADR references]. Focus areas: [specific concerns if any].",
  description: "Review [change]"
})
```

The `review` agent runs with fresh context on its configured model tier (set centrally in `availableAgents`, resolved via `models.*`). It has no knowledge of design discussions, implementation rationale, or the parent's thinking — it judges only what the code actually does. Its findings are evidence for the parent's review verdict.

The parent synthesizes: its own structural and DRY analysis (Steps 1-4) with the review agent's independent findings, then produces the final verdict.

Do NOT delegate when:
- The change is trivial (single-digit lines, obvious correctness)
- The review agent's findings would add no information beyond the parent's own review

## Process

### Step 1: Structural Overview

Before reading line-by-line, understand the shape of the change:

```
- Files changed: [count and names]
- Lines added/removed: [+N / -M]
- Cross-cutting or contained? [single module or spread across the codebase?]
- Architectural impact: [new modules? new dependencies? interface changes?]
```

If the diff exceeds 400 lines, stop. The change should be split into smaller, reviewable units. A large diff is a process smell — raise it.

### Step 2: Correctness

Verify behavior against the specification (from `spec-first`):

```
- Does every acceptance criterion have corresponding test evidence?
- Are edge cases from the specification handled?
- Are out-of-scope items genuinely not implemented?
- Is there any behavior not traceable to the specification? (scope creep)
```

A change that doesn't match its spec is a review failure regardless of code quality.

### Step 3: Cognitive Load Assessment

For each function/method introduced or modified:

```
1. Can a reviewer understand this function in under 60 seconds?
   - If no: too complex — extract, simplify, or document
2. How many things must the reviewer hold in working memory?
   - Variables in scope, conditional branches, loop nesting, state mutations
   - Score: more than 5-7 items = excessive cognitive load
3. Are there "surprising" behaviors?
   - Side effects not signaled by the function name
   - Implicit dependencies on global state
   - Non-local control flow (exceptions as control flow, callbacks that don't return)
```

Flag any function that exceeds these thresholds. The fix is structural (extraction, simplification), not commentary.

### Step 4: DRY Audit

```
1. Is any knowledge represented more than once?
   - Same validation rule in multiple places
   - Same error message string in multiple places
   - Same business rule expressed in different ways
2. Is any code structurally identical but semantically different?
   - ACCEPTABLE: two coincidentally similar functions serving different purposes
   - UNACCEPTABLE: the semantic difference is not obvious from context
3. Is there a missed opportunity for abstraction?
   - Three or more similar patterns → consider extraction
   - Two similar patterns → note for future, extract on the third occurrence
```

### Step 5: Naming Quality

Naming is a design activity. Review every new identifier:

```
- Does the name describe WHAT, not HOW?
  - Good: calculateOrderTotal() → what it computes
  - Poor: sumArrayReduce() → how it is implemented

- Is the name searchable?
  - Good: ProcessPayment() → findable
  - Poor: doIt(), handle(), process(), manage() → meaningless

- Is the name consistent with the codebase?
  - Same concept uses the same name everywhere
  - Different concepts use different names

- Is the name at the right abstraction level?
  - Module-level: domain concepts (Order, Payment, Customer)
  - Function-level: actions (validate, compute, persist)
  - Variable-level: precise (customerEmail, not str or data)
```

### Step 6: Error Handling

Every error path must be intentional:

```
- Is every error either handled or explicitly propagated?
- Are error messages actionable? ("Connection refused: port 5432 is not open" not "Error -1")
- Is the system's state consistent after an error?
  - No partial writes
  - No leaked resources
  - No silently swallowed exceptions
- Are there any empty catch blocks? (reject)
- Are there any catch(Exception) without re-throw or logging? (justify or reject)
```

### Step 7: Consistency Check

The change must be consistent with the existing codebase:

```
- Does it follow existing patterns or introduce new ones?
  - Existing pattern: acceptable without justification
  - New pattern: requires justification (ADR or comment)
- Are imports, formatting, and idioms consistent with the surrounding code?
- If the change introduces a new library or pattern, is it used consistently throughout?
- Does the change leave the codebase more or less consistent than before?
```

### Step 8: Summary and Verdict

Review summaries are ephemeral — they serve the merge decision and are not committed. The specification (`.spec.md`) and ADRs (`docs/adr/`) are the permanent record.

Produce a structured review summary:

```markdown
## Review Summary

**Verdict:** [APPROVE | APPROVE WITH SUGGESTIONS | REQUEST CHANGES | REJECT]

### Findings

#### BLOCKERS (must fix before merge)
- [Finding with specific line reference and rationale]
- [Finding with specific line reference and rationale]

#### WARNINGS (should fix, but may defer with explicit justification)
- [Finding with specific line reference and rationale]

#### SUGGESTIONS (consider, but reviewer's judgment applies)
- [Finding with specific line reference and rationale]

### Positive Observations
- [What was done well — be specific, not generic praise]

### Diff Statistics
- Files: N | +M / -K lines | Modules touched: X
```

## Evidence

After completing this skill:
- [ ] Structured review summary with verdict
- [ ] Specific findings with line references and rationale
- [ ] Cognitive load assessment for complex functions
- [ ] DRY audit result
- [ ] Error handling completeness check

## Exit Gate

Review is complete when:
- Every finding has a severity classification (BLOCKER/WARNING/SUGGESTION)
- BLOCKERS are concrete and fixable (not "this is bad" but "this specific line has this specific issue: here's why and here's what to do")
- Every BLOCKER has been either fixed (traceable to the finding) or explicitly rebutted with rationale; unresolved BLOCKERS are escalated to the human
- The verdict is clear and unambiguous
- The review is proportionate to the change size (a 10-line change doesn't get a 5-page review)

## Handoff

After this skill:
- If the change touches trust boundaries: **`security-review`** — independent security gate before merge
- Otherwise: the verdict is the final pre-merge gate. Proceed to **`commit-pr-hygiene`** if commits aren't yet structured for review, or **`integration-deployment`** if deployment follows the merge.

## Anti-Patterns

- **Rubber-stamp review**: "LGTM" without reading. If the review took less time than reading the diff, you didn't review it.
- **Bikeshedding**: Spending review energy on formatting and style while ignoring logic errors and architectural issues.
- **Scope creep in review**: Requesting changes unrelated to this change. "While you're here, also refactor module X" — file a separate issue.
- **Review by assertion**: "This is wrong" without explaining WHY it's wrong and WHAT the correct approach would be.
- **Perfect as enemy of good**: Blocking a correct, well-tested change because it could be slightly more elegant. Suggestions are suggestions; blockers are correctness or maintainability issues.
- **Personality-driven review**: "I wouldn't have done it this way" is not a finding. "This approach has the following concrete problems" is a finding.
