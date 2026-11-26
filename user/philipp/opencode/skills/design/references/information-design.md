# Information Design

## When to load & job

Use this for explanatory graphics, instruction panels, forms, and on-screen wayfinding. Arrange information around what someone needs to understand or do at each point. Information architecture decides where things live; this module decides how a person recognizes where they are and what comes next. If the primary job is comparing measurements, let data visualization lead. Produce a reading-size graphic or a walkable form slice; use an annotated study where policy, wording, or behavior is unresolved.

## Inputs & concepts

Get the current procedure, policy, and exceptions from its owner. Ask what people already know, what they have in front of them, and where they stop and return. Bring actual field wording, permitted formats, sample source documents, and the project's labels and components. For instructions, ask which parts and changes can be seen from the reader's working position. If the owner hasn't supplied an exception, show where it enters the known route and leave its instructions unresolved.

An **overview** explains relationships; a **sequence** depicts a change from one condition to another. A **precondition** is what must already be true before an action, and a **branch condition** is the fact that changes what happens next. A **recognition cue** lets a reader identify a part, screen, document, or completed state without interpreting an abstract instruction. For a form, a field's request, formatting hint, and example serve different roles. The prompt says what to enter; a hint says where to find it or how to write it; the example illustrates rather than supplies the answer.

## Decisions & procedure

- **Choose overview or sequence.** Use an overview where the reader needs to relate parts before acting. Use numbered panels where order changes the result. The panels reveal the next action but can hide how the parts fit together; sometimes one small locating view earns its space before the first panel.
- **Group by the source people hold.** Keep together fields copied from one document. Separate them when a decision makes them irrelevant or demands a different source. Separate steps reduce irrelevant detail but conceal the extent of the task, so name what people need up front.
- **Match progress to the route.** Number a stable sequence; for branching routes, name the current task and the remaining applicable tasks. This takes more space than a fixed count but avoids promising a route the process cannot honor.

1. Mark the entry point and the reader's intended end state. Build a **route-and-content map**: one row per task or recognition point, with the precondition, source in hand, instruction or question, visible result, and next route. Include a row for returning after an interruption if the procedure allows it.
2. Convert rows into panels or form groups. Label decision branches in the reader's vocabulary and put each prerequisite before the action that depends on it. When an instruction, label or error needs wording, use [UX writing](knowledge/ux-writing.md) (`references/knowledge/ux-writing.md`) to derive it from the system state and the next action. When an explanation includes a measured comparison, use [Data encoding](knowledge/data-encoding.md) (`references/knowledge/data-encoding.md`) to choose what the numbers should let the reader compare.
3. Lay out real wording at reading size. For repeated panels or responsive pages, use [Grid systems](knowledge/grid-systems.md) (`references/knowledge/grid-systems.md`) to keep related text and figures aligned and together as widths change. Stage one complete branch alongside the main route so the human can see what becomes irrelevant, what persists, and where the routes rejoin.

## Worked example & typical mistakes

An illustrative permits form asks people renewing an existing permit for its number and issue date; first-time applicants need neither. The map records “Already have a permit?” as a routing question, not as the first field in “Permit details.” The renewal row names the existing permit as its source and groups the two entries; the other route goes straight to contact details, where both routes rejoin. Put the document reminder next to the renewal option on entry. That placement lets a returning applicant fetch the permit before starting without suggesting a first-time applicant needs one. On a resumed renewal, show the named task, not a step total computed for the shorter route.

In an instruction panel, an arrow labeled “Turn” can read as a pointer to the filter cap instead of a motion cue. The reader finds the cap but doesn't know when to stop. Separate the part label from the curved arrow and show the supplied end state in the next panel.

## Standards, limits & handover

For web forms, W3C [WCAG 2.2](https://www.w3.org/TR/WCAG22/) (Recommendation, 12 December 2024), SC 1.3.1 and 3.3.2, address programmatically determinable relationships and labels or instructions for input. Use the [HTML Living Standard, “The label element”](https://html.spec.whatwg.org/multipage/forms.html#the-label-element), for the association a form prototype needs; a placeholder is not a persistent label. The [GOV.UK Design System, “Question pages”](https://design-system.service.gov.uk/patterns/question-pages/) is implementation guidance, not a universal requirement to put one question on each page. Field formats and exception routes are project rules; the permit example is illustrative.

Show the graphic at its reading size or walk the human through the form from entry to completion, including a known branch. Identify unresolved branches and who owns them. Ask what people need before starting, which decision changes the route, and where users can resume if they return.
