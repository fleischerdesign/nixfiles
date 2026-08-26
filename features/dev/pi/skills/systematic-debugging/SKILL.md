---
name: systematic-debugging
description: Scientific debugging methodology for isolating root causes. Use when encountering a bug, unexpected behavior, test failure, or any deviation from expected system behavior. Produces a minimal reproduction, a confirmed root cause hypothesis, and a verified fix. Do not fix until the root cause is proven.
---

# Systematic Debugging

Debugging is not patching. It is the application of the scientific method to a malfunctioning system. You do not guess, you do not "try something," and you do not change code until you understand why it is wrong.

## Theoretical Foundation

- **Scientific Method in Debugging** (Zeller 2009, *Why Programs Fail*): Observe → Hypothesize → Experiment → Refine. The same cycle that produced physics produces correct bug fixes. Every hypothesis must be falsifiable — if you can't design an experiment that could prove you wrong, your hypothesis is too vague.
- **Delta Debugging** (Zeller 2002): Systematically isolate the difference between a working state and a failing state. If a change introduced the bug, binary-search through the changes. If a specific input triggers it, minimize the input.
- **Five Whys** (Toyota Production System): For each symptom, ask "why did this happen?" until you reach the root cause — typically 3-5 levels deep. Stop when the answer is a process failure, not a code failure (e.g., "no test covered this edge case" is a root cause; "the variable was null" is not).
- **Reproduction is Everything**: A bug you cannot reproduce is a bug you cannot fix. Without reproduction, you are not debugging — you are speculating with a keyboard.

## Trigger

Load this skill when:
- A bug, crash, or unexpected behavior is reported
- A test fails and the cause is not immediately obvious
- Observed behavior diverges from expected behavior
- The user says "it's broken," "this doesn't work," "bug," "error," "crash"
- During any investigation where the system's behavior is surprising

Do NOT load this skill for:
- The bug's cause is immediately visible from the error message and stack trace
- The fix is trivial and obvious (typo, missing import, off-by-one with clear context)

## Process

### Step 1: Observe — Capture the Failure

Before forming any hypothesis, thoroughly observe the failure:

```
1. What is the EXACT error message? (copy-paste, do not paraphrase)
2. What was the EXPECTED behavior?
3. What was the ACTUAL behavior?
4. What are the EXACT inputs that trigger the failure?
5. What is the ENVIRONMENT? (OS, version, configuration, database state)
6. When did it LAST work? (specific commit, deployment, or time)
7. What CHANGED between then and now?
```

If any of these questions cannot be answered with specificity, your first task is to answer them — not to guess at a fix.

### Step 2: Reproduce — Make It Happen on Demand

```
1. Create a MINIMAL reproduction:
   - Remove everything that doesn't affect the bug
   - The smallest input, the simplest setup
   - Goal: a one-liner or minimal script that triggers the failure

2. Verify the reproduction is RELIABLE:
   - Run it 3 times — does it always fail?
   - If not, the bug is non-deterministic — that IS a clue

3. Document the reproduction:
   - Exact command or test case
   - Expected output vs actual output
```

A minimal reproduction is the single most valuable artifact in debugging. It is the experiment you will run to test every hypothesis.

### Step 3: Hypothesize — Form a Falsifiable Explanation

Generate 1-3 concrete hypotheses about the root cause:

```
Hypothesis 1: [Specific statement about what is causing the bug]
  - If this is true, then [specific prediction] should happen
  - Test: [concrete experiment that could prove this WRONG]

Hypothesis 2: [Alternative explanation]
  - If this is true, then [different prediction] should happen
  - Test: [concrete experiment that could prove this WRONG]
```

Rules for hypotheses:
- Must be specific: "a race condition in the connection pool" not "something with concurrency"
- Must be falsifiable: you can design an experiment that would DISPROVE it
- Must be code-localized: points to a specific module, function, or line
- Must explain ALL observed symptoms, not just some

### Step 4: Experiment — Test the Hypothesis

```
For each hypothesis, in order of likelihood:

1. Design the MINIMAL experiment:
   - If the hypothesis is correct, X should change when I change Y
   - The experiment must distinguish between competing hypotheses

2. Run the experiment:
   - ONE change at a time
   - If you change multiple things and the bug goes away, you learned nothing

3. Evaluate the result:
   - Hypothesis CONFIRMED: the prediction held — root cause identified
   - Hypothesis REFUTED: the prediction failed — discard this hypothesis
   - INCONCLUSIVE: the experiment design was flawed — redesign

4. If all hypotheses are refuted:
   - You missed something in observation — go back to Step 1
   - Gather MORE data: add instrumentation, trace the code path, examine state
```

Do not fix the bug yet. You are proving the cause, not patching the symptom.

### Step 5: Root Cause — Go Deep Enough

When a hypothesis is confirmed, ask WHY until you hit the root:

```
Symptom:    "NullPointerException on line 42"
Why?        → "userProfile was null"
Why?        → "the database query returned no rows for this user"
Why?        → "the user was created without a profile record"
Why?        → "the profile creation is in a separate, non-transactional step"
ROOT CAUSE: → "No atomicity guarantee between user creation and profile creation"
```

Stop when the root cause is a process or design failure. The fix at the root level is different from the fix at the symptom level:
- Symptom fix: add null check on line 42 (hides the bug)
- Root cause fix: wrap user + profile creation in a transaction (eliminates the class of bugs)

### Step 6: Prove — The Bug Is Gone

Before declaring victory:

```
1. Run the original reproduction:
   - The bug no longer manifests

2. Run the FULL test suite:
   - The fix didn't break anything else
   - Pay special attention to tests that touch the same module

3. Write a REGRESSION TEST:
   - A test that specifically catches this bug
   - The test must FAIL without the fix and PASS with it
   - This ensures the bug never silently returns

4. Scan for SIMILAR patterns:
   - Does the same root cause exist elsewhere in the codebase?
   - If yes: fix the class of bugs, not just this instance
```

## Evidence

After completing this skill:
- [ ] Bug report with exact error, expected/actual behavior, and environment
- [ ] Minimal reproduction (command or test case)
- [ ] Hypothesis log (which hypotheses were tested, which was confirmed)
- [ ] Root cause analysis (at least 3 Whys deep)
- [ ] Regression test that proves the bug is fixed
- [ ] Scan result for similar patterns

## Exit Gate

Debugging is complete when:
- The root cause is identified at the process/design level, not just the symptom level
- A regression test exists that would have caught this bug
- The fix addresses the root cause, not the symptom
- The full test suite passes

## Anti-Patterns

- **Shotgun debugging**: Changing random things until the bug disappears. You learned nothing and probably introduced new bugs.
- **Symptom patching**: Adding a null check, try-catch, or default value without understanding WHY the null/recoverable-state occurs. You silenced the messenger without reading the message.
- **Unreproducible speculation**: "Maybe it's the cache" without checking whether clearing the cache actually fixes it. Form a hypothesis, then test it.
- **Premature fix**: Jumping to a solution before understanding the cause. "I'll just rewrite this function" — if you don't know what's wrong with the current one, you'll make the same mistake in the new one.
- **Surface-level root cause**: "Variable was null" is not a root cause. "The initialization order is not enforced" is getting closer. "No static analysis prevents use-before-initialization" is a root cause.
- **Confirmation bias**: Only looking for evidence that supports your favorite hypothesis. Actively try to prove each hypothesis WRONG — the one that survives is your root cause.
- **Ignoring non-determinism**: A bug that reproduces "sometimes" is telling you something critical about its nature (timing, state, concurrency). Do not dismiss it as "flaky" — that is the most important clue.
