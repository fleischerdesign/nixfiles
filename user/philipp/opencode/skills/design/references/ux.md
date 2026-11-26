# UX (Usage Paths)

## When to load & job

Use this for usage paths: how someone gets from a starting situation to an outcome. Experience is an alias here. Work on sequence, friction, interrupted work and recovery rather than visual styling. Bring in Interaction when a particular control's response is the open decision; use UI for screen composition. Deliver a proposed task flow and a slice someone can walk through, not a collection of screens with the order inferred from their filenames.

## Inputs & concepts

Start with the person's goal, what they already know or have at hand, and realistic interruptions. Read existing flows, support reports and research; ask policy and service owners which decisions they make, what information is necessary, and what can be corrected or resumed. Separate observed work, reported problems and design hypotheses. Leave policy-dependent branches open when their owners haven't decided them.

A **step** changes what the person knows, has supplied or can do next; it need not be a screen. A **prerequisite** is a condition the next step depends on, not necessarily a field the person can answer now. A **commitment point** is where a consequential change takes effect. A **return point** is where an interrupted journey can continue with its context intact. “Submitted,” “received” and “decided” may be different outcomes: write each in language the person can recognize.

## Decisions & procedure

- **Guided branching versus one-pass entry.** Ask the question that changes which evidence a newcomer needs before presenting the rest. For repeat work with predictable requirements, keep relevant fields together so people can enter them in one pass. Guidance reduces simultaneous decisions but makes backtracking slower.
- **Review versus uninterrupted progress.** Let people revise reversible choices as they go. Insert a separate review before a consequential commitment when it makes a specific, otherwise difficult-to-correct mistake visible. Don't charge every user a pause just to repeat the form.
- **Resume versus start afresh.** Returning directly to an unfinished step avoids repeat work when evidence arrives later. Saved drafts introduce retention, device sharing and identity questions. Do not imply that work is saved until the product can say where and for whom.

1. Start a **branch-and-return map** with a real entry situation and the person's recognizable outcome. Name the open assumption most likely to change the order. When you need to learn what people bring or understand at entry, use [Research methods](knowledge/research-methods.md) (`references/knowledge/research-methods.md`) to connect that question to evidence.
2. Mark each branch with its deciding fact, who knows it, and the irreversible cost of learning it late. Put a decision before the work it makes unnecessary, but only at a point where someone can answer it. Give “I don't know” its own route when uncertainty is plausible; it is not a negative answer.
3. Add one interruption and return. For each branch write the information retained, the visible re-entry cue and the next useful step. If responsibility moves to staff or another channel, use [Service blueprint](knowledge/service-blueprint.md) (`references/knowledge/service-blueprint.md`) to clarify what the receiving role needs and who owns the case in the meantime.
4. Walk through the map using prompts, messages and a realistic record. If pending work or recovery changes what the interface can promise, use [Interaction states](knowledge/interaction-states.md) (`references/knowledge/interaction-states.md`) to specify that transition without turning every control state into a journey step.

## Worked example & typical mistakes

In an illustrative reimbursement flow, purchases made with a company card are reconciled elsewhere; personal purchases proceed to reimbursement. A delegate entering an expense may have the receipt but not know which card was used. On the map, put “How was this paid?” before receipt upload. The personal-card branch opens receipt intake; the company-card branch points to reconciliation. An “I don't know” branch tells the delegate where to find the payment method and returns to the question, not to the beginning. If drafts are allowed, the same return point can retain the expense already named without asking for a receipt that may never be needed.

Putting eligibility at the end makes some people complete an application they cannot submit. Moving it earlier but requiring a guess merely moves that failure. Routing uncertainty to clarification is what makes the earlier decision usable.

## Standards, limits & handover

[ISO 9241-210:2019](https://www.iso.org/standard/77520.html), *Human-centred design for interactive systems*, describes context of use and human-centred design activities; `verify` the exact clause in the applicable edition before making a normative claim. It doesn't supply eligibility, retention or review rules. Those are project specifications from the responsible owners. Branch maps are a working convention; the payment paths above are example policy, not recommendations about reimbursement.

Show the flow from entry to outcome, including the interruption and return, with sample messages and the information needed at each handoff. Label simulated behavior and unresolved policy. Ask what people actually have at entry, which actions can be undone after submission, and what retention and re-entry the service owner can support.
