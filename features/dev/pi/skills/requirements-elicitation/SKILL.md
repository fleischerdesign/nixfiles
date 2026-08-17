---
name: requirements-elicitation
description: Structured requirements gathering before specification. Use when a task is ambiguous, the user's intent is unclear, or acceptance criteria cannot yet be written. Produces clarified requirements, explicit non-functional needs, and a sign-off checkpoint before spec-first begins.
---

# Requirements Elicitation

You do not write a specification from assumptions. You write it from clarified, verified requirements. Elicitation is the phase where ambiguity is destroyed — every implicit expectation becomes an explicit requirement, every vague term gets a precise definition, and every conflict is surfaced before it becomes rework.

## Theoretical Foundation

- **Requirements Engineering** (IEEE 29148): Requirements are the statement of what a system must do. Elicitation is the systematic process of discovering, surfacing, and clarifying stakeholder needs. Without it, specifications are fiction derived from a single perspective.
- **Five Whys** (Toyota Production System): When a requirement is stated ("I need a login"), ask why until the underlying need is understood ("so that only authorized users can see their own data"). The first requirement is rarely the real requirement.
- **Non-Functional Requirements** (NFRs): Performance, security, availability, maintainability, scalability. These are equal citizens to functional requirements — a system that "works" but has 5-second latency does not work.
- **Active Listening** (Rogers, Gordon): Restate the user's request in your own words to confirm understanding before proceeding. "So you need X, which means Y must happen before Z, and the constraint is W. Is that correct?"

## Trigger

Load this skill when:
- A task description is ambiguous or underspecified
- The user says "I want something like..." or uses vague terms (fast, good, robust, nice)
- Acceptance criteria cannot yet be written in concrete Gherkin
- Multiple stakeholders or conflicting goals are implicit
- The task touches security boundaries, external APIs, or performance-sensitive paths and requirements are unclear
- `orchestration` classifies the task and requires elicitation before `spec-first`

Do NOT load this skill for:
- Trivial, fully specified tasks where every acceptance criterion is testable
- Typo fixes, formatting, or single-line config changes
- Tasks where the spec already exists and needs no clarification

## Process

### Step 1: Restate and Confirm

Restate the problem in your own words before any clarification:

```
Understood problem:
- [What the user appears to want, in precise terms]
- [What the constraints appear to be]
- [What the success criteria appear to be]

Is this understanding correct?
```

Never proceed without explicit confirmation. The user's "yes" is the contract for the rest of the elicitation.

### Step 2: Structured Clarification Questions

Ask targeted questions organized by concern:

#### Scope
- What is the boundary of this change? (files, modules, systems affected)
- What is explicitly OUT of scope? (deferred, separate issue, not needed)
- What is the minimum viable change? (MVP vs. nice-to-have)

#### Behavior
- What are the exact inputs, preconditions, and expected outputs?
- What should happen when inputs are invalid, missing, or extreme?
- What is the concurrency model? (single user, multi-user, parallel)
- What state persists across invocations? What is ephemeral?

#### Non-Functional
- Performance: latency budget, throughput requirement, resource constraints?
- Security: authentication, authorization, data sensitivity, threat model?
- Availability: uptime requirement, graceful degradation, failover?
- Compatibility: backward/forward compatibility, API versioning?

### Step 3: Explicitly Identify Non-Functional Requirements

List NFRs even when the user didn't mention them:

```
Identified non-functional requirements (confirm or correct):
- Performance: [latency/throughput if applicable; otherwise "not specified — default assumption: no regression"]
- Security: [auth/authz/data exposure if applicable]
- Availability: [uptime/resilience requirement]
- Observability: [logging, metrics, alerting]
- Maintainability: [testability, documentation, configurability]
```

Missing NFRs are not "out of scope" — they are unknown risks. Flag them.

### Step 4: Resolve Conflicts

Surface and resolve contradictions:

```
Conflict detected:
- Requirement A says [X]
- Requirement B says [not-X or incompatible-Y]
- Resolution: [proposed resolution or escalation to user]
```

A specification with unresolved conflicts is a guarantee of rework.

### Step 5: Sign-Off Checkpoint

Present the clarified requirements for explicit approval:

```
Clarified requirements for [task]:

Functional:
1. [Requirement — one sentence, testable]
2. [Requirement]

Non-functional:
3. [NFR with measurable threshold]
4. [NFR]

Out of scope:
- [Explicitly excluded]

Ready to proceed to specification. Confirm or correct.
```

The user's confirmation is the gate. No `spec-first` without it.

## Evidence

After completing this skill:
- [ ] Problem restatement confirmed by the user
- [ ] Structured clarification questions answered
- [ ] Non-functional requirements documented (even if "no explicit requirement" is the answer)
- [ ] Conflicts resolved or escalated
- [ ] Sign-off checkpoint accepted

## Exit Gate

Requirements are clarified when:
- Every term that was vague is now precise
- Every functional requirement is testable
- Non-functional requirements are stated or explicitly deferred with a rationale
- The user has explicitly confirmed readiness for specification

## Handoff

After this skill, the next step is:
- **`spec-first`** — write the specification from clarified requirements

## Anti-Patterns

- **Assumption-driven development**: Proceeding to specification without confirmed requirements. "I think they mean X" — ask, don't assume.
- **Shallow questioning**: Asking "anything else?" instead of structured, domain-specific questions. Generic questions get generic (useless) answers.
- **Skipping NFRs**: "They didn't mention performance, so it doesn't matter." Performance always matters; the question is the threshold.
- **Premature specification**: Writing Gherkin before requirements are clarified. The spec will encode assumptions, and those assumptions become defects.
- **Over-elicitation**: Spending more time on requirements than the change is worth. A 5-line change doesn't need 30 minutes of questioning. Right-size the elicitation to the risk.
- **Accepting "I don't know" without consequence**: "I don't know what the performance should be" is acceptable, but it must be RECORDED as an explicit uncertainty — not silently absorbed.
