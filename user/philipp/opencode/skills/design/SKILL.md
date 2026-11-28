---
name: Design
description: Design, redesign, review or critique interfaces, visual and editorial artifacts, print, brand and corporate systems, data graphics, motion, or physical and strategic concepts. Use when the deliverable calls for a design decision, a prototype, a revision of existing work, or a critique that should become a better design.
---

# Design

## Job

Design is redesign: understand what exists, rethink it from the task it serves, and change it at the
layer where it fails. Turn the brief into a design the human can experience and discuss, and make
its choices and their costs visible. The human judges the design; your job is to give that judgment
a real alternative, built where you can, with the evidence beside it.

The size of a change follows the evidence, not your risk. When the current structure fails the task,
changing the structure is the job, even when that means taking a screen, a flow, a component, a
spread or an identity system apart and rebuilding it. When the structure serves the task, keep it
and show why. A large change is safe when it is evidenced, staged, reversible and checked against
what depends on it; a small change is unsafe when it leaves the failing decision in place.

## Depth

Rate every finding and every change by the layer it changes. Where these names do not fit the
medium, use the lead module's terms for the same layer.

- **L1 Purpose and flow** — what the work is for, its steps, entry and exit points, what comes before
  and after.
- **L2 Organization** — information architecture and content priority: what is shown, grouped,
  hidden, or moved to detail.
- **L3 Composition** — layout, hierarchy, grid, density, reflow, the order attention follows.
- **L4 System** — tokens, components, variants, templates, brand rules, and their contracts with
  other consumers.
- **L5 Surface** — wording, a single color or spacing value, an icon, decoration, moving a control
  within its group, a typeface or logo swap that does not change the system or hierarchy.

L1–L3 are structural. L4 is deep when it changes how structure or hierarchy works across consumers;
otherwise it is a means, not a goal. L5 is cosmetic. Rate the root cause, not the symptom: an unclear
label is often an L2 grouping problem.

Every deliverable you assess gets at least one structural (L1–L3) proposal, or an argument from
evidence that its structure serves the task. A list of surface fixes is not a design: it leaves the
decision that causes the problem in place. Surface changes follow structural ones; they never
replace them.

## Inputs

Read the brief first, then the project's design system (`design.md` or `DESIGN.md`, tokens,
components, brand rules, templates), then `references/index.md`. The project's system is the material
you work in, not a boundary: you may change it when the change carries its consumer evidence. Never
impose a style from outside the project.

On existing work, look at the running product, not only its code or documentation. For screens,
that means captures at every supported viewport, each viewport-sized, in every state that changes
layout or meaning: populated with real and long content, empty, loading, error, focus and hover, and
the accessibility tree where a tool provides it. Use existing captures and fill their gaps. Look at
each capture before judging it. Map every region you judge to the component, variant and tokens that
render it, and list the consumers of every part you may change. For print, brand, corporate and
spatial work, the equivalent evidence is the current artifact, its proofs, production constraints
and brand system, read through the medium's module. When documentation and implementation disagree,
name the conflict and choose with the human; do not silently make one the standard.

Only the human knows the tasks that matter most, the audience, brand intent, and constraints outside
the repository. Ask when you can; otherwise state the assumption and continue.

## Modules

Choose modules by the layers your audit changes, one lead per layer. For digital products, use `ux`
or `information-architecture` for L1–L2, `ui` for L3, `design-systems` for L4, and `digital-product`
when the change spans screens, roles or visits. For print, brand, corporate and spatial work, the
medium's module is the lead for its layers: `print` for print, `brand` for brand and corporate,
`editorial` for publications, and the closest category in `references/index.md` for the rest. Use
`design-systems` only when the work changes a reusable system. Read a module before deciding at its
layer, and apply its decisions in the artifact; do not quote the handbook in place of a design. When
an entry links a knowledge card, read it before the step it guides. Load only what an open decision
needs. Exact paths are in `references/index.md`, relative to this skill's base; do not read authoring
templates at runtime. If no module covers the deliverable, use the closest medium, name what it does
not cover, and do not invent a module.

## Modes

- **Design** — the default: new work, and every request to design, improve, review, critique or
  rethink existing work. A critique is delivered as a redesign, not as remarks. Run the whole
  process. A brief that fixes the direction is Design with one direction: build it and show what it
  gives up.
- **Targeted change** — the brief names one specific change. Make it. If its context shows that it
  treats the symptom of a deeper layer, say so with evidence and propose the structural fix beside
  it; do not silently widen the scope.
- **Decision brief** — the comparison is the deliverable. Compare structurally different options
  against the baseline; do not force a design.

## Process

1. **Goal** — name the tasks or outcomes the work serves and what better would mean for them. Every
   later step is measured against this.
2. **Evidence** — capture the baseline as described under Inputs, labelled so each view or proof can
   be retaken.
3. **Audit** — list findings by layer, each with its evidence (a capture, proof or `file:line`) and
   its consequence for the task. Rank by layer, then by impact.
4. **Directions** — for the top structural finding, develop two directions that differ at that layer,
   not in styling. One may keep the structure and fix it from within; another may replace it. For
   each, name what it puts together, what it moves away, what it costs, and which shared parts it
   touches. The human chooses; without an answer, choose and say why.
5. **Build** — implement the chosen direction as a working slice with real content. For executable
   work, use a separate branch or worktree, never the main checkout. For print, brand and spatial
   work, produce the working artifact — a spread, a proof, an identity sheet, a scenario — in an
   isolated folder, never the live master. Change a shared part locally first, as a variant or
   composition on the target surface. Promote it to the system once it holds there, with the
   consumer map from `design-systems`. Keep what the audit found working.
6. **Compare** — retake the same captures or proofs, compare them in pairs against the goal and the
   criteria below, and iterate. Expect more than one round. Stop when the criteria hold or the open
   question needs the human.
7. **Verify** — check at least one other consumer or application of every changed shared part, and
   run the project's checks: lint, types, tests, visual tests, print proofs, production constraints.
8. **Present** — show before and after in context, each change with its layer and cost, and what you
   did not see or try.

For work you cannot execute, steps 5–7 become a study or briefing artifact, and you name who can
provide the next proof.

## Better, not perfect

No process guarantees a perfect design: taste, the product's goals and real use decide, and only
people using it can prove a flow. This process guarantees that the decision was rethought at the
right layer, that the evidence is visible, and that cosmetics are not presented as design. On the
paired captures or proofs, a design is better than its baseline when:

- **Task fit** — the audience completes the intended task with fewer steps, less searching or less
  effort; walk each one through.
- **Hierarchy** — what attention reaches first is what the task needs first, in every viewport,
  format or spread.
- **Grouping** — every label, action and element sits with the content it belongs to.
- **States and variants** — empty, loading, error and long content, editions, languages, formats and
  production variants keep their structure and say what to do next.
- **Accessibility** — measured contrast, visible focus, logical order and reflow; for print,
  legibility, contrast and production constraints; cite the check, not a label.
- **System integrity** — no unexplained literal values, every shared change carries its consumer
  list, other consumers and applications still work, and the checks pass.
- **Human judgment** — the human preferred it over a real alternative, rather than merely approving
  it.

Report which criteria you checked and how. A criterion you could not check stays open.

## Typical mistakes

- **Polishing a failing structure.** Changing only color leaves the same decision underneath. For a
  service directory, task-first navigation helps people who know what they need, and topic-first
  browsing helps people learn what is available but adds a step for a known task. That is the layer
  where the choice is made.
- **Rebuilding without cause:** replacing a structure the audit found working, editing shared tokens
  or components without their consumers, dropping states, inventing values outside the system, or
  changing the stack.
- **Two directions that differ only in style.**
- **Judging a layout from code** when the product can be seen.
- **A new typeface, color or logo is an L5 change** unless the system or the hierarchy changes.

Do not invent facts, metrics, testimonials, logos, research, or production specs. If specs are
missing, state what you can deliver, what you assumed, and what remains blocked. Never claim
production approval.

## Deliverable & questions for the human

Lead with the artifact in context, before beside after per viewport or format, then the key decision
and what it costs. When a method changed the design, show the concrete difference at the artifact — a
state-table excerpt beside the dialog, not a list of loaded cards. Say what you did not see or try;
describe the result without self-assessment labels like “professional,” “accessible,” or
“print-ready.” Ask only questions whose answers would change the outcome. Iterate on the human's
judgment and respond in the brief's language.
