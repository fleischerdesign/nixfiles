---
name: orchestration
description: Skill-chain decision engine. Classifies every non-trivial task into a workflow path and dispatches the correct skills and subagents. MUST be loaded at the START of any code change that is not provably trivial — before forming opinions, before writing specs, before exploration. The engineering-constitution's Mandatory Skill Dispatch mandates this.
---

# Orchestration

You do not decide ad-hoc which skills to load. You classify the task, consult the decision table, and execute the prescribed chain. Orchestration is the difference between a bag of skills and a pipeline.

## Theoretical Foundation

- **Workflow Engineering** (van der Aalst 2016): A workflow is not a suggestion. It is a directed graph of activities with defined preconditions and postconditions. Every task enters the graph at the correct node and exits at the correct node.
- **Right-Sizing Process to Risk** (your own Anti-Patterns): A 5-line typo fix does not run the same pipeline as a new authentication module. The orchestration skill enforces proportionality — not by skipping steps, but by classifying correctly.
- **Checksheets** (Gawande 2009, *The Checklist Manifesto*): A checklist is a cognitive safety net. The decision table is the checklist for the process itself — it catches the class of error where a task is misclassified and a critical skill is skipped.

## Trigger

Load this skill at the START of every non-trivial task. The engineering-constitution's **Mandatory Skill Dispatch** makes this a binding obligation: any code change that is not provably trivial MUST load this skill before anything else. Interactive exploration or "I know this codebase" is not a reason to skip — only category 1 (trivial) bypasses the pipeline.

Do NOT load this skill for:
- Trivial fixes where the task is fully self-contained and obvious (typo, formatting, single-line with clear correctness, rename — no behavior change)
- A task already classified as trivial by the dispatch rule

If you catch yourself mid-edit without having classified the task, stop and load this skill.

## Process

### Step 1: Classify the Task

```
Task type:
[ ] Trivial fix (typo, formatting, config, single-line with clear correctness, rename — no behavior change)
[ ] New feature (contained — new behavior inside an existing module; architecture is clear)
[ ] New feature (cross-cutting — new module, new dependency, or behavior spanning ≥2 modules)
[ ] Behavior change (existing code, new behavior, small to medium scope)
[ ] Bug fix (unexpected behavior, root cause unknown)
[ ] Refactoring (structural change, no behavior change)
[ ] Architecture change (new module, new dependency, new pattern)
```

### Step 2: Map to Workflow Chain

#### Decision Table

| Task Type | Chain | Rationale |
|---|---|---|
| New feature (cross-cutting) | `project-onboarding`(if new repo) → `requirements-elicitation`(if ambiguous) → `systematic-exploration` → `spec-first` → `architecture-design` → `tdd-discipline` → `mutation-testing` → `security-review`(if trust boundaries) → `commit-pr-hygiene` → `performance-verification`(if perf criteria) → `code-review` → `documentation-consistency` → `release-management`(if releasing) → `integration-deployment` | Full pipeline. Every gate fires. Specification and ADR produced. |
| New feature (contained) | `project-onboarding`(if new repo) → `systematic-exploration` → `spec-first` → `tdd-discipline` → `mutation-testing` → `commit-pr-hygiene` → `code-review` → `documentation-consistency` → `release-management`(if releasing) | Architecture is clear; skip architecture-design unless structure is affected. |
| Behavior change (small) | `systematic-exploration` → `spec-first` → `tdd-discipline` → `mutation-testing`(if logic-bearing) → `commit-pr-hygiene` → `code-review` → `documentation-consistency` | Small scope; skip architecture and security unless relevant. |
| Bug fix | `systematic-exploration`(if location unknown) → `systematic-debugging` → `spec-first`(if fix non-trivial) → `tdd-discipline` → `mutation-testing`(if logic-bearing) → `commit-pr-hygiene` → `code-review` → `documentation-consistency` → `post-mortem`(if significant) | Debug first, spec if needed, fix, then retrospective. |
| Refactoring | `systematic-exploration` → `systematic-refactoring` → `commit-pr-hygiene` → `code-review` → `documentation-consistency`(if docs affected) | Characterization tests, small steps, no behavior change. |
| Architecture change | `systematic-exploration` → `architecture-design`(→ ADR) → `spec-first`(optional) → `tdd-discipline` → `mutation-testing` → `code-review` → `documentation-consistency` | ADR required. Implementation may follow architecture. |

### Step 3: Load and Dispatch

1. Load the first skill in the chain.
2. Follow that skill's process; when its exit gate is met, move to its handoff target.
3. When a skill recommends subagent delegation, dispatch the correct subagent via `task`.
4. Track completion: when the chain reaches `code-review` and the verdict is APPROVE, the pipeline is complete.

### Step 4: Adapt and Short-Circuit

If at any point a skill reveals that the task is simpler than classified:
- Re-classify and switch to the lighter chain.
- Never skip a skill that has already been loaded and whose exit gate isn't met.

If a skill reveals the task is MORE complex than classified:
- Up-classify and add the missing skills.
- The chain is a lower bound, not a fixed path.

## Decision Table (Complete)

| Attribute | Light Chain | Full Chain |
|---|---|---|
| Intensity | Typo, config, single-line, obvious correctness | Multi-module, new abstraction, unfamiliar code |
| Skills | Direct to `tdd-discipline` or skip (for trivial) | Full exploration → spec → architecture → TDD → mutation testing → review → doc consistency → release |
| Subagents | None or single `implement` | `explore` → `implement` + `review` + `security-reviewer`(if relevant) |
| Artifacts | None or minimal | Spec (.spec.md), ADR (if architecture), review verdict |
| Gate | Build + tests pass | All of Full Chain + security sign-off |

## Evidence

After completing this skill:
- [ ] Task classified (type from decision table)
- [ ] Chain selected with justification (which skills are in, which are out)
- [ ] Chain loaded or handoff to first skill executed

## Exit Gate

Orchestration is complete when:
- The first skill in the chain has been loaded and its process has begun
- The remaining chain is documented as the path for this task

## Handoff

To the FIRST skill in the selected chain — never to the user with "here's what I'll do." The user sees the work, not the plan.

## Anti-Patterns

- **Orchestration theatre**: Loading this skill, classifying, then ignoring the chain. Classification without execution is procrastination.
- **Rigid chain enforcement**: Refusing to skip `spec-first` for a 3-line bug fix because "the table says." The table is guidance, not law. Override with explicit justification.
- **Chain skipping without justification**: "I know what to do, I don't need exploration." The decision table exists because gut feelings are unreliable. Justify every skipped skill.
- **Process as product**: Spending more time on the chain than on the implementation. A 10-minute feature with a 30-minute pipeline is a pipeline failure, not a feature success.
- **Task misclassification**: Classifying a new authentication module as "contained feature" because "I understand authentication." Classification is about the CODEBASE impact, not your domain knowledge. A change that touches auth, sessions, cookies, and database is cross-cutting regardless of your expertise.
