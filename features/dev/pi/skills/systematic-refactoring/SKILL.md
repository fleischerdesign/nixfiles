---
name: systematic-refactoring
description: Safe structural change without behavior change. Use when restructuring code that has no tests or incomplete coverage — before adding features, after understanding the code, when reducing technical debt. Produces characterization tests, small reversible steps, and verified behavior preservation. Never refactor and add features in the same change.
---

# Systematic Refactoring

Refactoring is changing structure without changing behavior. It is the foundation of sustainable code — without it, every feature adds complexity until the codebase calcifies. You do not refactor by instinct. You refactor in small, verified, reversible steps, backed by tests that prove behavior is preserved.

## Theoretical Foundation

- **Characterization Testing** (Feathers 2004, *Working Effectively with Legacy Code*): When code has no tests, you cannot refactor safely. First, write tests that capture what the code *actually* does — not what it *should* do. These are characterization tests, not specification tests. They are your safety net.
- **Parallel Change / Expand-Contract** (Nygard 2007, *Release It!*, Fowler): When changing a public interface, you cannot break callers. Expand: add the new interface alongside the old. Migrate: move callers one by one. Contract: remove the old interface when nothing uses it. At every point, the system works.
- **Composed Method** (Beck 1997, *Smalltalk Best Practice Patterns*): A method should operate at a single level of abstraction. If one method mixes low-level iteration with high-level policy, split them. Extract Method until every function does one thing.
- **Strangler Fig Pattern** (Newman 2015, *Building Microservices*): Replace a system incrementally by routing new behavior to the replacement while the old system still runs. Eventually, nothing routes to the old system — remove it. Applies to modules, not just services.
- **Refactoring vs. Rewriting** (Fowler 1999): Refactoring is a series of small transformations. Rewriting is a single large replacement. Refactoring lets you stop at any point with a working system. Rewriting is binary — it works or it doesn't.

## Trigger

Load this skill when:
- You need to restructure code before adding features ("make the change easy, then make the easy change" — Kent Beck)
- Code has no tests or incomplete coverage and you need to modify it
- A module's interface needs to change without breaking consumers
- The user says "refactor," "clean up," "restructure," "extract," "simplify"
- Technical debt is blocking development and needs reduction

Do NOT load this skill for:
- Changes that alter behavior — refactoring preserves behavior; if behavior must change, plan the behavior change first
- Trivial renames or formatting changes where the tool handles it automatically

## Process

### Step 1: Map the Surface

Identify the boundaries of the refactoring:

```
1. What module/functions are in scope?
2. Who calls them? (every caller — grep exhaustively)
3. What tests exist? (coverage on the target code)
4. What interfaces are public (stable) vs private (changeable)?
5. What is the target state? (one sentence — e.g., "Extract validation logic into a separate module")
```

Never start without answering all five questions. Guessing callers is how refactoring breaks production.

### Step 2: Build the Safety Net

If test coverage is incomplete — which it always is when refactoring is needed — write characterization tests:

```
1. For every public function in scope, write a test that calls it with:
   - The happy path input
   - Null/empty/zero input
   - One known edge case from reading the code

2. The test asserts the CURRENT behavior, even if it seems wrong.
   // Characterization test — captures actual behavior
   test("formats date as MM/DD/YYYY", () => {
     expect(formatDate("2024-01-15")).toBe("01/15/2024");
   });

3. Run these tests — they MUST pass. If they don't pass, you don't
   understand the code yet. Go back to Step 1.

4. Aim for: every code path in scope is exercised by at least one
   characterization test.
```

The safety net proves you understand the current behavior. Without it, you are refactoring blind.

### Step 3: Perform Small Verified Steps

Each step must be a single, named refactoring from the catalog (Fowler 1999):

```
Safe refactorings (one per step, verify after each):
- Extract Method — pull a block of code into a named function
- Inline Variable — replace a temporary with its expression
- Move Function — relocate to a more appropriate module
- Rename Variable/Function — clarify intent
- Introduce Parameter Object — group related params
- Replace Conditional with Polymorphism — dispatch by type
- Extract Class — split a module that has multiple responsibilities
```

Rules:
- **One transformation per step.** "Extract method AND rename" is two steps.
- **Tests stay green after every step.** Any failure → revert immediately.
- **Commit after each successful step.** Small commits make bisect and code review trivial.
- **The system works at every intermediate point.** There is no "broken state."

### Step 4: Parallel Change for Public Interfaces

When the refactoring changes a public API, use Expand-Contract:

```
1. EXPAND: Add the new interface alongside the old one.
   - New function lives next to old function
   - Old function can delegate to new function internally
   - Both coexist — the system works

2. MIGRATE: Move callers to the new interface.
   - One caller per commit (not batch)
   - Tests verify each caller after migration
   - Use deprecation warnings on the old interface during transition

3. CONTRACT: Remove the old interface.
   - Only when zero callers remain (grep confirmation)
   - If a deprecation period is needed, schedule removal with a ticket
   - Remove the code, not just mark deprecated
```

Never break a public interface without an Expand-Contract plan. The caller you didn't find is the one that breaks production.

### Step 5: Verify Behavior Preservation

Before declaring the refactoring complete:

```
1. All characterization tests pass.
2. All existing tests pass (no regressions).
3. For renamed/deleted symbols: grep — no remaining references.
4. For moved modules: imports updated in every calling file.
5. For extracted functions: old call sites route through the extraction
   (or the extraction is unused → was it truly needed?).
6. Git diff: structure changed, behavior identical.
   // Verify: git diff -w shows no logic changes
```

If any step reveals behavior differences — you introduced a change, not a refactoring. Revert to the last green state and redo.

### Step 6: Clean Up

After verification:

```
1. Remove any test that was purely a characterization test and is now
   redundant with existing specification tests.
2. Update any documentation that references changed module names.
3. Note in the commit: "Pure refactoring — no behavior change."
```

## Evidence

After completing this skill:
- [ ] Surface map (callers, interfaces, target state)
- [ ] Characterization tests for all code paths in scope
- [ ] Commit history of small, named refactoring steps
- [ ] Expand-Contract plan executed (if public API changed)
- [ ] Verification: all tests green, git diff -w clean on behavior
- [ ] Old interfaces removed or deprecation tickets filed

## Exit Gate

Refactoring is complete when:
- Behavior is proven identical (characterization tests + git diff -w)
- Every commit is a single named refactoring
- The code is simpler — a new team member can explain the module in under 2 minutes
- No "while I was here" changes crept in

## Anti-Patterns

- **Refactoring without tests**: "I'm just moving code, it'll be fine." It won't. Write characterization tests first — even one test that verifies the module's primary output catches most regressions.
- **Refactoring + feature**: "While I'm restructuring this, I'll also add the new field." Every behavior change is a risk. Structure change is a risk. Combined, they are impossible to reason about independently. Separate PRs.
- **Big-bang restructuring**: "I'll rewrite the module on a branch." 400 lines later, the branch conflicts with main, tests don't pass, and you've lost track of which change caused which failure. Small steps, merge frequently.
- **Breaking callers silently**: "Nobody else uses this function." Unless you've grepped the entire codebase, you don't know. Always grep, always check monorepo-wide.
- **Cosmetic refactoring**: Renaming `i` to `index` and calling it a day. Refactoring must reduce cognitive load measurably. If the change doesn't make the code easier to understand, it's churn.
- **Perfection paralysis**: "Let me restructure the entire module before I touch it." Refactor only what you need to make the next change easy — no more. The rest is technical debt with a known interest rate.
