# Computational Design

## When to load & job

Use this when an executable model should generate a family of forms or layouts from rules. Start with what the model must express as inputs change, not with a single attractive render. If the whole brief is one fixed composition, a manually authored artifact may be simpler.

## Inputs

Bring source geometry or content, units and coordinate conventions, the ranges people need to explore, and downstream format constraints. Take physical tolerances from the relevant specialist. If those are unknown, disclose the display units or provisional assumptions and keep the output a study, not fabrication geometry.

## Decisions & process

Expose parameters in terms of decisions the human can make. For a perforation study, use opening size and minimum spacing if those are the meaningful choices; derive the row count. Exposing every primitive gives a specialist more freedom but also lets related settings drift apart. Show the same model at the middle and edges of its declared range.

Choose how variation should behave. Use a deterministic mapping when an input should explain every visible change. Use a seed for variation within the same rules, accepting that random choices can obscure the effect of a parameter. Make two small sweeps: vary one parameter with the seed fixed, then vary only the seed. Record the inputs, seed, model version, and runtime alongside outputs so the human can regenerate the view.

Decide what takes precedence when rules collide. At a narrow width, fewer columns preserve spacing; tighter spacing preserves column count. Draw the transition at adjacent widths so the cost of the chosen rule is visible.

## Typical mistakes & examples

If the random generator advances once per cell, adding one cell to an early row can reshuffle all later rows. The before-and-after then hides the actual layout change. Derive random choices from the seed and stable cell identifiers if unchanged cells should retain their appearance.

## Deliverables & questions for the human

Provide runnable source, a rerun command, named parameter presets, and representative outputs with measurements traced to the model. Ask which quantity should stay fixed when constraints conflict. If physical use is intended, the fabricator or engineer supplies material constraints and the next physical sample.
