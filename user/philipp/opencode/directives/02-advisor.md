# Independent second opinion: the Advisor subagent

This section addresses the agent that calls the Advisor; the Advisor itself ignores it.

A global `Advisor` subagent, launched with the subagent tool, gives an independent second opinion. It
runs in a fresh child session with its own context and model. It can read and search anywhere, run
shell commands, inspect processes, use the web, Code Mode, MCP and Fleet, including `fleet_run` for
remote diagnosis. It does not edit files, launch subagents or sessions, ask the user, or write notes, todos or
schedules. Its shell, `fleet_run` and OpenChamber tools are not sandboxed: staying in the diagnosis
role is an instruction, not enforcement.

## When to call it

Call it when the user asks for it: "frag den Advisor", "Sag es dem Advisor", "hol eine zweite
Meinung ein", "ask the Advisor", "run it by the Advisor". A mention of the Advisor is not an
instruction; only a request is.

Call it on your own judgment when the decision is hard enough that an independent check is worth the
cost: an architecture or contract choice with lasting consequences, a bug whose evidence conflicts,
a review of a risky or irreversible change, or a plan whose next step is expensive to undo. Do not
call it for routine edits, facts one read settles, style preferences, or as a rubber stamp before
work you have already decided to do.

## How to brief it

Send the smallest brief that lets it judge:

- the question, in one or two sentences;
- the context and constraints that decide it;
- what was tried and what happened;
- the files, commands or sources that matter;
- the host and revision, when the answer depends on remote state;
- what you need back: a verdict, a design, ranked hypotheses, or a review.

State the question neutrally. If you have a leaning, label it as a claim to test.

Point at evidence instead of pasting it. The Advisor investigates on its own. Do not send the whole
conversation.

## How to use the answer

The Advisor's report is advice, not authority. Verify the claims that matter, especially anything it
marks unverified, and keep ownership of the change and the final check. One call per decision; at
most one targeted follow-up if new evidence appears. Do not ping-pong between agents.

Its report arrives when the child session goes idle; wait for it before acting on the decision it
covers.
