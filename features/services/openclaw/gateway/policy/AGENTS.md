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

## Remote execution

Keep parent conversations and orchestrating subagents on the Gateway unless the user
explicitly requests another session-placement mode. Native child completion is the
handoff; `sessions_yield` announces children, and a collector follows its own accepted
contract. Never replace a completion contract with a model-driven status loop.

Give each writing child an isolated managed worktree. Verify the parent-to-child source
binding and inherited bytes before editing; never accept a default-workspace fallback for
repository work. Session placement and SSH execution are separate facts: a device chosen
in a client UI does not select a build executor, and a native pairing id is not an SSH
identity.

A native managed-worktree child inheriting a parent's dirty, untracked, deleted or
executable state is not established. Do not assume it and do not describe it as working:
until a verified checkpoint or explicit source protocol is accepted, treat that path as an
unproven source handoff and capture the intended input through `remote-exec`.

Edit canonical source on the Gateway. For a selected-node build or test, run
`remote-exec run` with a declared inventory host, an explicit identity file, repository
and run ids, and the command. That is the whole operation: it captures the current
working tree with Git's own project rules, transfers it to a fresh attempt directory,
verifies the pinned host key, non-root account, root ownership, input and cwd, and only
then executes and observes the terminal result. Do not split it into manually coordinated
prepare/sync/verify steps, and do not assume a node already holds the source. Edits made
after one invocation are captured by the next; a running attempt keeps its input.

`capture`, `verify`, `status` and `collect` exist for inspection, recovery and delta
integration. `exec` with `host=<node>` is raw execution: it does not export or verify
repository source, and it must not be used as a substitute for `remote-exec run`.
Do not hand-roll an rsync/ssh upload or a second ignore list.

Execution identity comes from the inventory and the executor module: the account, root
and pinned host key are declared there. The executor key is a dedicated non-root
credential; never use a root deploy key, never run a build as root, and never accept an
arbitrary account or root path from a task.

An attempt runs under the executor account's systemd manager, so it survives an SSH
disconnect. An attempt id is dispatched at most once: a duplicate or concurrent request
observes the original and never reruns or overwrites its result. A successful tool call,
an elapsed timeout or a Stop request is not proof of success or termination. Use
`remote-exec status` to reconcile and `remote-exec cancel` to stop the unit; cancellation
is reported only after the unit and its process tree are gone. Unknown stays unknown.
Do not replay an uncertain write through another transport.

Prefer build/test-only attempts. Collection returns the recorded input paths plus new
source that the project's own `.gitignore` rules admit; ignored build trees, dependency
directories and the rest of the work tree stay on the executor. Artifacts are requested
separately. `collect --delta` returns a verified export for the integrator's normal Git
workflow; this tool never applies a delta to the live parent. Never overwrite the parent,
never run `rsync --delete` into it, and never edit both copies concurrently.

Do not transfer credentials, agent state, credential-bearing Git configuration, `.git`
metadata or unrelated caches. The tool refuses `.env`, private-key, SSH and agent-state
paths independently of Git ignore rules, but that is a name boundary: a semantic secret
under an ordinary name still leaves the executor account as the trust boundary. Build-time
secrets need separately authorized injection and must not enter source or results.

The caller is the sole writer for the duration of a capture; the tool detects selection,
index, HEAD and content changes instead of claiming an atomic snapshot of a multiwriter
tree. The tool enforces path containment, input identity, attempt ownership, single
dispatch and unit/process-tree cancellation. It does not enforce that a command is safe
to run on shared external state, nor that the caller actually stopped writing.
