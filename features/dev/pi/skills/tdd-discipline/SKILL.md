---
name: tdd-discipline
description: Test-Driven Development with rigorous RED-GREEN-REFACTOR cycles. Use for all implementation after a specification and architectural design exist. Produces test-first code, property-based tests for invariants, mutation testing evidence, and F.I.R.S.T.-compliant test suites. Never write production code before its test exists.
---

# TDD Discipline

You do not write production code first and "add tests later." You write the test, watch it fail, write the minimum code to make it pass, and then refactor. This cycle is non-negotiable for any logic-bearing code.

## Theoretical Foundation

- **Test-Driven Development** (Beck 2002): RED → GREEN → REFACTOR. The test is the first consumer of your interface. If the test is hard to write, the interface is wrong — fix the interface, not the test.
- **F.I.R.S.T. Principles**: Tests must be Fast, Independent, Repeatable, Self-validating, and Timely (written before the code).
- **Property-Based Testing** (QuickCheck/Hedgehog): Instead of hand-writing examples, declare invariants and let the framework generate counterexamples. Catches edge cases you didn't think of.
- **Mutation Testing** (DeMillo 1978, modern: Stryker/PIT): Intentionally inject bugs into your code and verify that tests catch them. Code coverage is a proxy; mutation testing measures test quality directly.
- **Test as Documentation**: A test suite is the most reliable form of documentation. It cannot go out of date because it is verified on every run.

## Trigger

Load this skill when:
- A specification exists and implementation is the next step
- Writing, modifying, or refactoring any logic-bearing code
- A bug is being fixed (write a regression test first)
- The user asks to "add tests" or mentions TDD

Do NOT load this skill for:
- Configuration files, documentation, or non-executable artifacts
- Generated code (but the generator should be tested)
- Trivial glue code with no logic (but verify this judgment — "trivial" code often hides bugs)

## Subagent Delegation

For changes touching 2+ non-trivial modules or >50 lines of new logic, delegate implementation to an `implement` subagent with the specification and architectural plan:

```
Agent({
  subagent_type: "implement",
  prompt: "Implement [spec reference]. Specification: [summary]. Architecture: [key decisions]. Files to modify: [paths]. Existing patterns to follow: [patterns]. Out of scope: [explicitly].",
  description: "Implement [feature]",
  isolation: "worktree"
})
```

The `implement` agent runs with `deepseek-v4-flash` and `tdd-discipline` skill preloaded. It implements in an isolated worktree. The parent reviews the resulting branch with `code-review` + `reviewer` subagent before merging.

Do NOT delegate when:
- The change is a single function in a single file
- The implementation is trivial (< 30 lines, straightforward)
- The specification is still being clarified

## Process

### Step 1: RED — Write a Failing Test

Write exactly one test that captures the next increment of behavior:

```
Rules for the RED phase:
- The test must fail for the RIGHT reason (assertion failure, not compilation/setup error)
- The test name describes the behavior: "rejects_empty_input" not "test_validate_1"
- The test covers exactly one behavior — one assertion per test, or closely related assertions
- The test is independent — it does not depend on other tests running before or after
```

Structure:

```gherkin
Given: [arrange — set up the test context]
When:  [act — invoke the behavior under test]
Then:  [assert — verify the expected outcome]
```

If the test is hard to write, stop. The interface is badly designed. Fix the design first. TDD exposes design flaws before they become code.

### Step 2: GREEN — Minimum Code to Pass

Write the absolute minimum code to make the test pass:

```
Rules for the GREEN phase:
- No code beyond what the test requires
- No refactoring yet (even if the code is ugly)
- No "future-proofing" — the test doesn't need it, you don't write it
- If the "minimum" is more than a few lines, the test may be too large — split it
```

The goal is speed through the RED-GREEN cycle. Each cycle should be seconds to minutes, not hours.

### Step 3: REFACTOR — Improve Without Changing Behavior

Now make the code clean while keeping all tests green:

```
Rules for the REFACTOR phase:
- Tests must stay green throughout
- Remove duplication (in both production code AND tests)
- Improve names, extract methods, reduce complexity
- Apply patterns discovered during implementation, not speculated before it
```

The refactor step is not optional. Skipping it creates technical debt. The discipline is: RED→GREEN moves you forward; REFACTOR keeps the ground clean behind you.

### Step 4: Property-Based Tests (for algorithmic or data-transform code)

When the code transforms data, has invariants, or processes input:

```
1. Identify invariants:
   - Round-trip: encode(decode(x)) == x
   - Idempotence: f(f(x)) == f(x)
   - Monotonicity: if a < b, then f(a) <= f(b)
   - Symmetry: f(a, b) == f(b, a) (if applicable)

2. Express as property tests with generated inputs
3. Run with increasing input sizes
4. If a counterexample is found, add it as a concrete regression test
```

Property-based tests complement example-based tests. Examples verify known cases; properties discover unknown failures.

### Step 5: Mutation Testing Gate

Before declaring the test suite complete:

```
1. Run mutation testing on the changed code
2. Every mutant must be killed by at least one test
3. Surviving mutants indicate:
   - Missing test cases → add them
   - Dead code → remove it
   - Equivalent mutant → document why it's not killable
4. Target: 100% mutation score on changed code
```

Mutation testing is the honesty check. Coverage says "this line was executed." Mutation says "this line's behavior is verified."

### Step 6: Test Suite Hygiene

Before the cycle is complete:
- [ ] All tests pass (non-negotiable)
- [ ] Tests are independent (any subset can run in any order)
- [ ] No sleeping/waiting in tests (use deterministic time if needed)
- [ ] No network or filesystem dependencies (mock or use test doubles)
- [ ] Tests run in under 5 seconds for the changed module
- [ ] Test names describe behavior, not implementation

## Evidence

After completing this skill, the following exist:
- [ ] RED phase log: which test was written, why it failed (not compilation)
- [ ] GREEN phase log: what minimal code was added
- [ ] REFACTOR phase log: what was improved without behavior change
- [ ] Property-based tests for data-transform or algorithmic code (if applicable)
- [ ] Mutation testing report showing 100% kill rate on changed code

## Exit Gate

TDD is complete for this change when:
- Every behavior in the specification has at least one test
- Every test follows F.I.R.S.T. principles
- Property-based tests cover identified invariants
- Mutation testing reports no surviving mutants (or documented equivalents)
- The REFACTOR phase has been executed at least once

## Handoff

After this skill, the next step is:
- **`code-review`** — verify the complete change before committing

## Anti-Patterns

- **Test-last development**: Writing code first, then retrofitting tests. The tests will confirm what the code does, not what it should do.
- **Over-mocking**: Mocking everything except the class under test. Tests that mock 10 collaborators verify nothing — they are a tautology. Mock at module boundaries, not internal collaborators.
- **Testing implementation, not behavior**: Tests that break when you refactor without changing behavior. Tests should verify WHAT, not HOW.
- **Coverage chasing**: 100% line coverage with assertions that don't verify behavior. `assertTrue(true)` passes coverage but proves nothing.
- **Skipping REFACTOR**: The test is green, move on. This is the most common TDD failure mode. Without refactoring, RED→GREEN alone produces a tangled mess.
- **Giant RED-GREEN cycles**: A test that requires 100 lines of production code to pass. The test is too coarse — split the behavior into smaller increments.
- **Testing external systems**: Tests that call real APIs, databases, or file systems are integration tests. They have value but are not unit tests and do not belong in the fast TDD cycle.
