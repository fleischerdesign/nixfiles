---
name: spec-first
description: Specification-Driven Development. Write the specification before writing code. Use for any non-trivial feature, bug fix, or behavior change. Produces user stories, acceptance criteria (Gherkin), edge case enumeration, and out-of-scope declarations. Load this before any implementation begins.
---

# Specification-First Development

You do not start with code. You start with a specification. The spec is the contract between intent and implementation — it defines what "done" means before a single line is written.

## Theoretical Foundation

- **Specification-Driven Development** (Fowler 2025): In the AI era, the spec is the primary human-agent interface. Without a written spec, both human and agent operate on assumptions that diverge silently.
- **Behavior-Driven Development** (North 2006): Specifications expressed as concrete examples are testable, unambiguous, and serve as living documentation.
- **Given-When-Then** (Gherkin): A structured format that forces explicit thinking about preconditions, actions, and postconditions.

## Trigger

Load this skill when:
- A new feature or behavior change is requested
- A bug report needs root-cause analysis before fixing
- A requirement is ambiguous and needs clarification
- Any task that will touch more than one function or module
- The user asks "how should this work?" or similar

Do NOT load this skill for:
- Trivial typo fixes or formatting changes
- Single-line configuration changes with obvious intent
- Tasks where the specification is already written and agreed upon

## Process

### Step 1: Understand the Problem

Read the relevant code, documentation, and issue context before forming an opinion. Ask clarifying questions if requirements are ambiguous. Your understanding must be grounded in the actual codebase, not assumptions.

Output: A one-paragraph problem statement in plain language.

### Step 2: Define the User Story

```
As a [specific role or persona]
I want [concrete capability or behavior]
So that [measurable outcome or value]
```

The story must be verifiable. "Better performance" is not a story. "Response time under 200ms at p95 for 1000 concurrent requests" is a story.

### Step 3: Write Acceptance Criteria (Gherkin)

Express acceptance criteria as Given-When-Then scenarios:

```gherkin
Feature: [Brief feature description]

  Scenario: [Happy path]
    Given [precondition]
    When [action]
    Then [expected outcome]

  Scenario: [Edge case]
    Given [precondition]
    When [action]
    Then [expected outcome]

  Scenario: [Error case]
    Given [precondition]
    When [invalid action]
    Then [error behavior — not silently ignored]
```

Rules for scenarios:
- Every happy path has at least one edge case and one error case.
- Preconditions are explicit and reproducible.
- Expected outcomes are observable, not internal state descriptions.
- Error cases specify the exact error behavior — "throws an error" is insufficient.

### Step 4: Enumerate Edge Cases

Systematically list edge cases the scenarios cover, and those they do not:

```
Covered:
- Empty input → [scenario reference]
- Maximum input size → [scenario reference]
- Concurrent access → [scenario reference]

Not covered (explicitly out of scope for this change):
- Network partition recovery
- Backward compatibility with v1 API
```

Every edge case is either covered by a scenario or explicitly declared out of scope.

### Step 5: Declare Out of Scope

What this change does NOT do:

```
Out of scope:
- Performance optimization of the query path
- Migration of existing data
- UI for configuration (CLI only in this iteration)
```

Out-of-scope declarations prevent scope creep and set reviewer expectations.

### Step 6: Validate the Spec

Before implementation begins, verify:
- Every acceptance criterion is testable (can be automated)
- Edge cases are either covered or declared out of scope
- Out-of-scope items are specific and intentional
- The spec is small enough to implement in one focused session
- No implementation details leak into the spec (the spec describes WHAT, not HOW)

## Evidence

After completing this skill, the following artifacts exist:
- [ ] Problem statement (1 paragraph)
- [ ] User story (As a/I want/So that)
- [ ] Acceptance criteria (Gherkin scenarios, minimum 3: happy, edge, error)
- [ ] Edge case enumeration (covered + out of scope)
- [ ] Out-of-scope declaration
- [ ] Specification saved to `src/<module>/<feature>.spec.md` alongside the primary module

## Exit Gate

The spec is complete when:
- A reviewer can read it and unambiguously determine whether any given behavior is correct
- No scenario references implementation details
- Edge case coverage is explicit (covered or declared out of scope)

## Handoff

After this skill, the next step is one of:
- **`architecture-design`** — if the change crosses module boundaries or introduces new abstractions
- **`tdd-discipline`** — if the change is contained within existing modules and architecture is clear

## Anti-Patterns

- **Spec as afterthought**: Writing the spec after the code to justify what was built. The spec must precede implementation.
- **Unverifiable scenarios**: "The system should be fast" or "should handle errors gracefully." These are not testable.
- **Implementation leakage**: Spec mentions classes, functions, or data structures. The spec describes behavior, not design.
- **Spec overload**: A 50-line spec for a 5-line change. The spec's weight should match the change's risk.
- **Skipping edge cases**: "We'll handle that later." Either cover it now or explicitly declare it out of scope.
