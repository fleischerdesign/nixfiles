---
name: nf-delegation
description: Run a substantial, self-contained assignment in a child session and return evidence to the parent.
---

# Delegated work

Use this when one worker can complete a clear, bounded assignment and the parent should keep the
decision.

## Workflow

1. Write the work package: goal, inputs and paths, write scope, constraints, acceptance checks and
   the expected result format.
2. Choose an existing subagent that fits the work. Do not create a role or model only for this task.
3. Start the child with the package. Let it investigate, implement, test and repair ordinary
   failures.
4. Do not poll the child as a timer. Wait for its completion event, or inspect it only when a
   decision needs the current state.
5. Check the artifact and the test evidence yourself. Integrate the result or return the blocker.

## Template

Use `references/work-package.md`.
