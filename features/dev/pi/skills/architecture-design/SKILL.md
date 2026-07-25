---
name: architecture-design
description: Structural design and architectural decision-making. Use when changes cross module boundaries, introduce new abstractions or dependencies, or require trade-off analysis between design alternatives. Produces C4-style context analysis, module boundary definitions, dependency direction validation, and Architectural Decision Records (ADRs).
---

# Architecture Design

Code structure is not an afterthought. It is the primary lever for managing complexity over time. Every module boundary, dependency, and abstraction is an architectural decision — make them intentionally.

## Theoretical Foundation

- **Information Hiding** (Parnas 1972): Modules should encapsulate design decisions that are likely to change. The interface exposes WHAT; the implementation hides HOW. This is not about access modifiers — it is about designing modules around their secrets.
- **Deep Modules** (Ousterhout 2018): The best modules have simple interfaces and complex implementations. A deep module does a lot with a small API surface. Shallow modules — thin wrappers, pass-through functions, one-line callers — create interface bloat without hiding complexity.
- **C4 Model** (Brown): Architecture is communicated at four levels: System Context (the world), Containers (deployable units), Components (logical subsystems), and Code (classes/functions). Switch levels deliberately.
- **Architectural Decision Records** (ADRs): Lightweight, immutable records of significant decisions. Each ADR captures the context, the decision, the alternatives considered, and the consequences. ADRs are written before or during the decision, never after.

## Trigger

Load this skill when:
- A change crosses module or service boundaries
- A new abstraction, interface, or dependency is introduced
- You are choosing between two or more structural alternatives
- A dependency direction question arises (who depends on whom?)
- The user asks about "structure," "architecture," "modules," or "design"
- `spec-first` handoff indicates architecture work is needed

Do NOT load this skill for:
- Changes entirely within a single function
- Bug fixes that don't alter structure
- Adding a function to an existing module that follows established patterns

## Subagent Delegation

When the change affects 3+ modules or a broad area of the codebase, dispatch `Explore` subagents for read-only reconnaissance before making architectural decisions:

```
Agent({
  subagent_type: "Explore",
  prompt: "Map all modules that handle [domain]. For each: public interface, dependencies, and what knowledge it hides. Report file paths and key symbols.",
  description: "Map [domain] modules",
  run_in_background: true
})
```

Dispatch one Explore per affected domain in parallel (background). Collect results, then proceed with Steps 1-6 in the parent. The parent owns architectural decisions — subagents provide evidence, not judgments.

## Process

### Step 1: System Context (C4 Level 1)

Describe the system and its external relationships:

```
System: [Name]
External actors: [Users, external systems, databases, APIs]
Data flow: [What enters, what exits, in which direction]
```

This is the "who talks to whom" diagram — in prose. If the change doesn't alter the system context, state that explicitly.

### Step 2: Container/Component Impact (C4 Level 2-3)

Identify which deployable units and logical subsystems are affected:

```
Affected containers/components:
- [Component A]: [How it changes and why]
- [Component B]: [How it changes and why]

Unaffected but adjacent:
- [Component C]: [Why it is NOT changed despite being related]
```

### Step 3: Module Boundary Analysis

For each new or changed module, answer:

1. **What is this module's secret?** (What design decision does it hide from the rest of the system?)
2. **What is its interface?** (What does it expose? Keep it minimal.)
3. **Is it deep?** (Does the interface hide substantial complexity, or is it a shallow wrapper?)
4. **What is its single responsibility?** (If you need "and" to describe it, split it.)

A module without a secret is a namespace, not a module.

### Step 4: Dependency Direction

Analyze and justify the dependency graph:

```
[A] depends on [B] because: [reason grounded in stability — B is more stable/abstract than A]

Dependency rules (apply to every edge):
- Stable → Stable: acceptable if both are concrete
- Unstable → Stable: ideal direction
- Stable → Unstable: suspect — justify explicitly
- Cyclic: rejected — break with interface or restructure
```

The dependency rule: depend in the direction of stability. Concrete code depends on abstract code. Application code depends on library code. Not the reverse.

### Step 5: Alternatives Analysis

Document at least two alternatives with trade-offs:

```
Alternative 1: [Description]
  Pros: [List]
  Cons: [List]
  Rejected because: [Specific reason]

Alternative 2 (chosen): [Description]
  Pros: [List]
  Cons: [List with mitigation]
  Chosen because: [Specific reason grounded in principles]
```

One alternative must always be "do nothing / status quo" — what happens if we defer this change?

### Step 6: Architectural Decision Record (if significant)

Write an ADR if the decision is:
- Hard to reverse (database schema, API contract, file format)
- Cross-cutting (affects multiple teams or modules)
- Novel (introduces a pattern not yet established in the codebase)
- Contentious (genuine trade-off between valid alternatives)

```markdown
# ADR-[NNN]: [Title]

**Status:** Proposed
**Date:** [YYYY-MM-DD]
**Context:** [What problem are we solving? What constraints exist?]
**Decision:** [What did we decide? Be specific.]
**Alternatives Considered:**
- [Alternative A]: [Why rejected]
- [Alternative B]: [Why rejected]
**Consequences:** [What becomes easier? Harder? What must we do next?]
```

Save ADRs to `docs/adr/NNN-lowercase-title.md`. Check existing ADRs for the next available number. Never delete or renumber — supersede with a new ADR.

### Step 7: Architecture Overview

After significant architectural changes, update `docs/architecture/overview.md`:

```markdown
# Architecture Overview

## System Context
[Who talks to whom — external actors, data flow]

## Components
| Component | Responsibility | Interface | Depends On |
|-----------|---------------|-----------|------------|
| [Name]    | [One sentence] | [What it exposes] | [Other components] |

## Key Decisions
- [ADR-001: Title](adr/001-title.md) — [One-line summary]
- [ADR-002: Title](adr/002-title.md) — [One-line summary]

## Technology Stack
[Key technologies with rationale]
```

Create `docs/architecture/` and the overview if they don't exist. This document is onboarding material — keep it concise, update it on significant changes.

## Evidence

After completing this skill, the following artifacts exist:
- [ ] System context description (or explicit "no change" statement)
- [ ] Affected component analysis
- [ ] Module boundary analysis for each new/changed module
- [ ] Dependency direction justification
- [ ] Alternatives analysis (minimum 2 alternatives)
- [ ] ADR saved to `docs/adr/NNN-title.md` (if the decision meets significance criteria)
- [ ] `docs/architecture/overview.md` updated (if the architecture changed)

## Exit Gate

Architecture design is complete when:
- Every new module has an identified secret and a minimal interface
- Every dependency edge has a justified direction
- At least one alternative was seriously considered and rejected with reasons
- Significant decisions are recorded as ADRs

## Handoff

After this skill, the next step is:
- **`tdd-discipline`** — implementation with test-first discipline

## Anti-Patterns

- **Analysis paralysis**: Spending more time on architecture than implementation. The ADR should be proportional to the decision's weight.
- **Big Design Up Front**: Designing the entire system before any code. Design enough for the current slice, with awareness of future slices.
- **Shallow modules**: Creating interfaces that expose more than they hide. A module with 10 public methods and 20 lines of private implementation is a code organization mechanism, not an architectural achievement.
- **ADR theatre**: Writing ADRs after the code is merged to document what was built. ADRs capture the decision process, not the outcome.
- **Missing "do nothing" alternative**: Every design discussion must consider the cost and risk of the change itself against the status quo.
- **Premature abstraction**: Extracting a "reusable" module before you have at least three concrete use cases that demonstrate the abstraction is correct.
