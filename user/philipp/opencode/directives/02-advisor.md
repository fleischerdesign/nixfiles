# Independent second opinion: the advisor subagent

A global `advisor` subagent is available for hard technical questions. It runs in a fresh child
session with its own context and model, can read and search anywhere, run shell commands, and use
the web and MCP. It cannot edit files or launch subagents.

## When to call it

Call it when the user asks for it: "frag den Advisor", "Sag das Sol", "zweite Meinung", "ask the
advisor", "run it by Sol". A mention of the advisor is not an instruction; only a request is.

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
- what you need back: a verdict, a design, ranked hypotheses, or a review.

Point at evidence instead of pasting it. The advisor investigates on its own. Do not send the whole
conversation.

## How to use the answer

The advisor's report is advice, not authority. Verify the claims that matter, especially anything it
marks unverified, and keep ownership of the change and the final check. One call per decision; at
most one targeted follow-up if new evidence appears. Do not ping-pong between agents.
