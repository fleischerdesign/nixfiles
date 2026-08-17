---
name: mutation-testing
description: Verify test-suite quality by injecting faults and measuring whether tests catch them. Use after TDD for logic-bearing code where tooling exists and risk justifies it. Produces a mutation score and a classification of every surviving mutant.
---

# Mutation Testing

Coverage says "this line was executed." Mutation testing says "this line's behavior is verified." You have just written a test suite in `tdd-discipline` — this skill is the honesty check on whether those tests actually protect the behavior they claim to.

## Theoretical Foundation

- **Mutation Testing** (DeMillo, Lipton & Sayward 1978): Inject small syntactic faults ("mutants") into the code and run the test suite. A mutant that changes observable behavior and is not caught by any test has *survived* — it is a blind spot in the suite.
- **Coupling Effect / Competent Programmer Hypothesis** (DeMillo 1978): Programmers write code that is nearly correct. Tests that catch simple faults tend to catch complex ones, so a high kill rate on simple mutants is strong evidence of suite quality.
- **Equivalent Mutants**: Some mutants are semantically identical to the original (e.g., `x < 0` → `x <= 0` when `x` is an integer). These cannot be killed by any test — they must be recognized and documented, not "fixed."
- **Test Oracle Problem** (Weyuker 1982): A test only verifies what its assertions check. A passing suite may be asserting the wrong things; mutation testing exposes exactly which assertions are missing.

## Trigger

Load this skill when:
- `tdd-discipline` implementation is complete and the suite is green
- The changed code is logic-bearing (parsing, validation, data transformation, auth, payment, state transitions)
- The user asks to assess test quality or "is this tested enough?"

Do NOT load this skill for:
- Configuration, documentation, or non-executable artifacts
- Glue code with no logic (verify this judgment — "trivial" code often hides bugs)
- Languages/toolchains where no mutation framework exists (document the gap, do not block)

## Process

### Step 1: Risk & Tooling Assessment

```
Risk level:
- HIGH   (money, auth, data loss, security): thorough mutation testing required
- MEDIUM (business logic, data transforms): mutation testing on changed code
- LOW    (formatting, config, glue): document the skip, proceed

Tooling by language:
- JavaScript/TypeScript → Stryker
- Java → PIT
- Python → mutmut or Cosmic Ray
- Rust → cargo-mutants
- Ruby → mutant
- Go → go-mutesting / gremlins
- No tooling available → document as technical debt, flagged gap, hand off
```

### Step 2: Scope the Analysis

```
1. Run on CHANGED code only — never the whole repository (slow, noisy)
2. Select mutators relevant to the change:
   - Arithmetic operators (+, -, *, /)
   - Boundary conditions (<, <=, >, >=, ==, !=)
   - Return values (replace with null/empty/constant)
   - Conditional branches (negate, remove)
3. Exclude generated code, test helpers, and third-party vendored code
```

### Step 3: Run and Read the Score

```
Mutation score = killed / (killed + survived)

- Run the mutation framework on the changed module
- Record: total mutants, killed, survived, timed-out (count as killed)
- HIGH-risk code: zero surviving mutants (or a documented, justified exception)
- MEDIUM-risk code: high score; every survivor classified
```

### Step 4: Classify Every Survivor

A surviving mutant is exactly one of three things — never leave it unclassified:

```
1. Missing test → the suite has a blind spot. Write the regression test
   that kills it (return to `tdd-discipline` RED→GREEN for that behavior).
2. Dead code → the mutated line has no effect on any output. Remove it.
3. Equivalent mutant → semantically identical to the original.
   Document WHY it is equivalent (with the reasoning), do not delete it silently.
```

### Step 5: Close the Loop

```
1. After fixes, re-run the analysis
2. Confirm the score improved and every survivor is classified
3. Record evidence: score, survivor list, actions taken
4. Attach the report to the change for `code-review`
```

## Evidence

After completing this skill:
- [ ] Risk level assessed (HIGH/MEDIUM/LOW)
- [ ] Tooling identified, or gap documented as technical debt
- [ ] Mutation report on the changed code (score, mutant counts)
- [ ] Every survivor classified (missing test / dead code / equivalent mutant)
- [ ] Actions executed and re-run verified

## Exit Gate

Mutation testing is complete when one of these holds:
- Every surviving mutant is classified and the appropriate action (add test / remove dead code / document equivalent) is done
- The gap is documented as technical debt (no tooling available)
- The risk assessment concluded mutation testing is not justified (LOW risk) — with the reasoning recorded

## Handoff

After this skill:
- **`code-review`** — with the mutation report attached as evidence of test quality

## Anti-Patterns

- **Coverage as a substitute**: 100% line coverage with weak assertions passes the coverage tool but survives mutation. Coverage is a proxy; mutation is the measurement.
- **Whole-repo runs**: Running mutation testing on the entire codebase produces slow, noisy results that get ignored. Scope to changed code.
- **Score-chasing on low-risk code**: Spending hours pushing a config module to 100% mutation score. Right-size to risk.
- **Equivalent-mutant denial**: Deleting or "fixing" an equivalent mutant without documenting why it is equivalent. The documentation is the point.
- **Tooling-blocked paralysis**: No mutation framework for the language, so the whole pipeline stalls. Document the gap and proceed — it is technical debt, not a blocker.
