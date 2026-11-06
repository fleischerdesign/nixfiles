# Delegated work policy

This file is managed by Nix. Change its source in nixfiles, not this deployed copy.
It complements personal workspace instructions and task-specific skills. Model references
and execution limits belong to OpenClaw configuration, not to these instructions.

## Ownership

In the main conversation, own the user intent, important decisions, integration and
acceptance. In a delegated run, own only the assigned scope and report to the requester;
do not repeat the global planning process or create another coordinator. Keep dependent
steps with the same owner. Delegate further only when the assignment warrants it.

## Model and context budget

Use the configured default subagent model for ordinary execution. Override it with a
premium model only when the task requires its judgment; do not copy the main model into
every spawn. Premium time is for understanding, decisions and acceptance, not routine
progress handling. Small or tightly coupled tasks may be completed directly.

Use isolated child context with a sufficient brief; fork the conversation only when
its history is genuinely necessary. Keep large logs and exploration in the worker
context. Return concise evidence, not the whole transcript. Give each worker enough
scope to complete ordinary investigation, implementation and verification without
routine owner intervention; batch independent work and consolidate results when
possible. Do not poll as a timer or repeat completed work just to obtain status. Do
not silently switch to a paid fallback or downgrade a decision that needs premium
judgment.

## Work packages and parallelism

Give workers a goal, relevant paths, scope and constraints, acceptance checks, and an
expected result format. Let them investigate, implement, test and repair ordinary
failures within one substantial assignment. A durable plan is useful for large work,
not mandatory paperwork for every task.

Do not impose an arbitrary short `runTimeoutSeconds` on delegated work. Omit it to use
OpenClaw's configured default unless the task has a concrete deadline or operational
reason for a shorter limit; allow for provider retries and multi-step work. A timeout
is not proof that work had no effect: inspect the retained session and any external
state before continuing or replaying actions. A timeout is distinct from rate limiting;
do not restart completed or potentially non-idempotent actions blindly.

Parallelize independent work when it reduces elapsed time. Respect configured limits,
shared files, external state and provider throughput. More slow workers are not proof
of greater throughput. Use disjoint write scopes or managed worktrees; their results
still require integration and checks together. Do not split a dependency chain into
separate workers merely to increase the worker count.

## Escalation and acceptance

Workers escalate conflicting requirements, out-of-scope architectural changes and
blocked work with evidence and a precise question. After two failed repair attempts
without new evidence, stop the loop and ask the owner to reconsider the approach.

Report changes, checks and outcomes, open risks and decisions needed. The owner checks
the actual artifacts and relevant test evidence, not just a success claim. Add an
independent, clean-context review when impact justifies it; do not require a separate
premium review for every routine change. Consolidate related results before making
the next decision where completion semantics permit; retain ownership until done.

## Background work

Create routine automation agent turns with an explicit `background` model alias.
Heartbeats and memory maintenance have their own configured model. Explicitly discuss
any exception that needs premium reasoning. Runtime jobs, auth and memory remain
runtime-owned; do not edit Nix-owned configuration to make temporary changes permanent.
