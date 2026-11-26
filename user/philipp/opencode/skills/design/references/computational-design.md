# Computational Design

## When to load & job

Use this when an executable model should generate a family of forms or layouts from rules. Start with what the model must express as inputs change, not with a single attractive render. If the whole brief is one fixed composition, a manually authored artifact may be simpler.

Lead here when the rule and its controls are part of the deliverable. Use visual design for a manually composed layout and the relevant physical discipline when the deliverable is engineered or fabrication geometry. A runnable study can expose that later decision without settling it.

## Inputs & concepts

Get source geometry or content, units, axes, origin and downstream format constraints from the consuming team. Ask which differences people want to explore and what must stay fixed. Only a relevant specialist or supplier can specify manufacturing tolerances. Without them, state the display units and provisional ranges and keep the result a study.

An **independent control** expresses an intended choice; a **derived quantity** follows from the inputs and model rules. If width and minimum spacing are independent, a column count inferred from them cannot also be freely specified. A **discrete transition** occurs when a small input change adds or removes a whole element. A **seed** identifies a starting state for a pseudorandom process, not a persistent identity for each generated element. Keep the model separate from the renderer so labels and exports can use the measured geometry rather than infer it from pixels.

## Decisions & procedure

- Expose opening size and minimum spacing when those are the human choices; derive the count. Exposing primitives gives specialists more control but allows related settings to drift apart.
- Prefer a deterministic mapping when one input should explain the visible change. Use seeded variation when multiple expressions are useful under the same rules, but show it separately so it doesn't disguise the input's effect.
- Preserve spacing by dropping a column at narrower widths, or preserve count by tightening spacing if spacing is flexible. Centering the remaining array redistributes the edges; anchoring it keeps one edge fixed and moves the unused width to the other.

1. Draw the **dependency map** from inputs to output dimensions. Include units, precedence where choices collide, and which values appear in the interface versus the export. For setting exploratory ranges and separating parameter effects from seed effects, use [Parametric variation](knowledge/parametric-variation.md) (`references/knowledge/parametric-variation.md`).
2. Implement the layout as a function that returns geometry and derived measurements. Explicitly represent cases such as a panel too narrow for one opening; draw the empty panel with an explanation rather than silently packing a smaller opening. Pass this result to the renderer and keep display zoom out of the model.
3. Build reference, edge and transition presets, and arrange representative outputs at the same scale. Use the card to produce separate parameter and seed views. Label what changed and put the actual model dimensions under each output rather than quoting nominal input alone.
4. Record control values, seed if used, generator revision, runtime and source inputs with the exported versions. Include a rerun command and make the rendering destination explicit.

## Worked example & typical mistakes

An illustrative panel has usable width `W` after fixed margins, opening width `d`, and minimum gap `g`. A row of `n` openings needs `n*d + (n-1)*g` for `n ≥ 1`, so for positive `d` and nonnegative `g` derive `floor((W+g)/(d+g))` openings when `W ≥ d`, and none otherwise. With `d = 12` and `g = 4` display units, a width of `59` leaves `15` unused units after three openings and two gaps; `60` fits four exactly. Centering puts `7.5` on either side at `59` but none at `60`. Draw those adjacent presets to show why the first opening moves even though width changed by only one unit. These values illustrate the rule; they are not tolerances.

Drawing one random choice per cell from a single sequence can reshuffle downstream rows when a column is added. If surviving cells should retain their appearance, derive choices from the seed and stable row and column identifiers rather than each cell's index in the flattened array.

## Standards, limits & handover

For an original rule-based generation model, see Prusinkiewicz and Lindenmayer, *The Algorithmic Beauty of Plants* (1990), chapter 1, “Graphical Modeling Using L-Systems.” It is a method, not a norm. The official p5.js references for [`randomSeed()`](https://p5js.org/reference/p5/randomSeed/) and [`noiseSeed()`](https://p5js.org/reference/p5/noiseSeed/) document distinct controls; `verify` the pinned runtime version and do not assume identical output across versions. Gap precedence is a model convention unless the supplier specifies it; manufacturing limits are project specifications.

Hand over runnable source, the rerun command, named presets and representative outputs tied to model measurements. Ask which quantity should stay fixed when rules conflict. The fabricator or engineer supplies material constraints and the next physical sample; software geometry alone does not establish material behavior.
