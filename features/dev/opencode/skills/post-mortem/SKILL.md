---
name: post-mortem
description: Blameless post-incident review. Use after a significant bug, deployment failure, or production incident to understand root causes and prevent recurrence. Produces a timeline, root cause analysis, action items, and a workflow retrospective that feeds back into the skill chain.
---

# Post-Mortem

Every incident is a free lesson — but only if you capture it. A post-mortem is not about blame. It is about understanding the chain of events that led to failure, the decision points where the outcome could have changed, and the process changes that prevent recurrence.

## Theoretical Foundation

- **Blameless Post-Mortems** (Allspaw 2012, Etsy): Focusing on "who caused this" destroys the information needed to prevent the next incident. The operator who made the mistake was following a process that permitted the mistake. Fix the process, not the person.
- **Five Whys Extended** (Toyota, adapted for software): From `systematic-debugging`, the root cause is traced to a process or design failure. The post-mortem extends this: given the root cause, what prevented it from being caught earlier? Each missed detection is a separate line of inquiry.
- **Swiss Cheese Model** (Reason 1990): Accidents occur when holes in multiple layers of defense align. A bug slips past tests, past review, past staging, into production. The post-mortem identifies every layer that failed and closes at least the first hole.
- **Learning Organization** (Senge 1990): Organizations that capture and disseminate lessons from incidents outperform those that "move on." A post-mortem that isn't read is an incident that happened twice.

## Prerequisite

Load **`systematic-debugging`** first if the bug's root cause hasn't been established. The post-mortem requires a confirmed root cause, not a hypothesis.

## Trigger

Load this skill when:
- A production incident has been resolved
- `systematic-debugging` has identified a root cause at the process/design level
- A deployment was rolled back (`integration-deployment` handoff)
- A significant bug was fixed that should have been caught earlier in the pipeline
- At regular intervals (monthly/quarterly) for aggregate process health

Do NOT load this skill for:
- Trivial bugs caught in development with no process implications
- Incidents still in progress (finish `systematic-debugging` first)
- Minor regressions with root causes that are fully explained by the fix itself

## Process

### Step 1: Incident Timeline

Reconstruct the sequence of events:

```
Timeline (UTC):
- [timestamp]: [event — what happened, who detected it, how]
- [timestamp]: [response action]
- [timestamp]: [resolution — what stopped the incident]

Detection method: [monitoring alert / user report / team member noticed]
Time to detect (TTD): [duration from first symptom to detection]
Time to resolve (TTR): [duration from detection to resolution]
```

A precise timeline is the skeleton of the post-mortem. Without it, the narrative is opinion.

### Step 2: What Went Well

Every incident has successful aspects. Document them to reinforce:

```
What went well:
- [Detection: alert fired within 30 seconds of error spike]
- [Response: on-call engineer acknowledged within 2 minutes]
- [Communication: status page updated within 5 minutes]
- [Resolution: rollback completed in 90 seconds]
```

If nothing went well, the post-mortem is incomplete — even "the team assembled quickly" is a positive to capture.

### Step 3: What Went Wrong — Root Cause Chain

Extend the root cause from `systematic-debugging` to the process level:

```
Symptom: [what users experienced]
Immediate cause: [code-level failure]
Why? → [reason]
Why? → [reason]
Why? → [root cause at process/design level]
Why? → [systemic cause: why did the process allow this?]

Example:
Symptom: Users saw 500 errors for 12 minutes
Immediate cause: NullPointerException in payment service
Why? → session token was null
Why? → token rotation failed mid-request
Why? → rotation had no error handling for concurrent access
Why? → token rotation was added as a hotfix without spec or review
ROOT CAUSE: → No gate prevented merging hotfixes without the standard pipeline
```

### Step 4: Missed Detection Points

Identify every layer of the pipeline that SHOULD have caught this:

```
Detection layers and why each failed:
- [ ] Unit tests: [did tests exist? did they cover this path?]
- [ ] Spec: [was the behavior specified?]
- [ ] Architecture review: [was the design reviewed?]
- [ ] Code review: [was the diff reviewed? why wasn't this caught?]
- [ ] Security review: [did this touch trust boundaries? were they checked?]
- [ ] Performance verification: [did the change affect latency/throughput?]
- [ ] Staging: [was it tested in staging? why didn't it fail there?]
- [ ] Monitoring: [was there an alert? did it fire in time?]
```

A detection layer that "wouldn't have caught this" is a process DESIGN failure — the layer should exist for this class of error.

### Step 5: Action Items

Each action item must be specific, assigned, and scheduled:

```
Action items (SMART):
1. [Specific action] — Owner: [who], Due: [date], Tracking: [issue/ADR]
2. [Specific action]

Action types:
- Preventive: code change that eliminates the root cause
- Detective: test/monitor that catches this class of error next time
- Process: change to the pipeline (new gate, review checklist, deploy procedure)
```

### Step 6: Workflow Retrospective

This is the META-ANALYSIS that closes the feedback loop:

```
Workflow retrospective:
1. Which skills were loaded for this change?
2. Did the skill chain include any detection layer that failed?
   - If yes: why did that skill not catch this?
   - If no: should a skill have been loaded? (update orchestration decision table)
3. Was a skill missing entirely that would have caught this?
4. Was the skill chain executed correctly but the output was ignored?
5. What change to the skill content, decision table, or agent configurations
   would have prevented this incident?

Potential improvements to the engineering workflow:
- [Specific change to a SKILL.md file — file a task]
- [Specific change to orchestration decision table]
- [Specific change to agent configuration]
```

This step is what separates a post-mortem from a retrospective — it closes the loop on the META-SYSTEM: the skills and processes themselves.

## Evidence

After completing this skill:
- [ ] Incident timeline with TTD and TTR
- [ ] What went well documented (even if minimal)
- [ ] Root cause chain (minimum 4 Whys deep, ending at process failure)
- [ ] Missed detection points enumerated with analysis
- [ ] SMART action items assigned and tracked
- [ ] Workflow retrospective with concrete skill/process improvements identified

## Exit Gate

Post-mortem is complete when:
- The root cause is understood at the process/design level
- At least one action item addresses the FIRST missed detection point
- The workflow retrospective has produced feedback for the skill chain
- ARchived in a discoverable location (linked from the related spec or ADR)

## Handoff

After this skill:
- Action items → file issues or tasks
- Workflow improvements → update skills or orchestration decision table
- No incident summary → the post-mortem is the permanent record; it IS the archive

## Anti-Patterns

- **Blame-seeking**: "Who approved this?" → "What in the review process failed to catch this?" The answer to the second question prevents recurrence. The answer to the first prevents nothing.
- **Root cause at code level**: "The fix is to add a null check." The root cause is not the null — it's the process that allowed untested code to merge. The null check fixes the symptom; the process change fixes the disease.
- **Action-item theatre**: "We'll add more tests" with no specific test, no owner, and no due date. An action item without an owner is a wish.
- **Skipping the workflow retrospective**: The incident is about the code, not the skills. But every incident is a stress test of the ENTIRE pipeline. If review missed it, the review process needs scrutiny. If the spec didn't cover it, the spec process needs improvement.
- **Post-mortem as afterthought**: Writing it two weeks later from memory. The timeline is already hazy, the evidence is stale, and the learning is compromised. Write it within 24 hours of resolution.
- **No dissemination**: The post-mortem exists in a file nobody reads. Link it from the spec, from the ADR, from the relevant code. The next developer working in this area must know what happened here.
