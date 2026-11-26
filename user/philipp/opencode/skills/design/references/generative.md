# Generative & Creative Coding

## When to load & job

Lead here when the artifact is a system that makes a family of outputs: a procedural pattern, a live sketch, or an interactive composition. Build a runnable sketch and a sheet of related outputs so the human can explore the behavior rather than judge one striking frame. Use computational design when the central task is encoding constraints for a designed object, and image-making when the deliverable is a selected image rather than the means of generating it.

## Inputs & concepts

Bring visual or behavioral references, a description of what must remain recognizable, and any inputs that drive variation. Ask the installation or production owner for runtime, device, display dimensions, interaction hardware and export constraints. If the venue is unknown, name the prototype environment and treat installation performance as open. Gather source assets and their usage terms; substitutions can change the generated family.

An **invariant** is what the family keeps, such as a silhouette or connection rule. A **grammar** determines what structures can occur; a **parameter** steers visible variation within or between structures. A **seed** selects a repeatable realization under a given generator and inputs, not an art-direction axis like density. **Simulation state** evolves over time; a render is a view of that state. Keep them separate when redraws, resizing, or export should not change the composition.

## Decisions & procedure

- **Family resemblance versus discovery.** Fix the growth grammar and vary spacing or direction when the outputs need a recognizable silhouette. Vary the grammar itself if unexpected structures are the point, accepting that some outputs may stop reading as a family. Compare rule changes using the same seeds.
- **Independent controls versus useful coupling.** Separate randomness for palette and structure when a color edit should not redraw the geometry. A shared stream is simpler and can give pleasing coupled changes, but the relationship becomes difficult to direct. If density should affect saturation, write that dependency into the design instead of relying on incidental draw order.
- **Live response versus export fidelity.** Reuse generated structure or cap work per update for a live piece, giving up some density or fidelity. Spend more work offline for a higher-fidelity export if live exploration is not needed. Show the difference on the available device and label any different target assumptions.

1. Draw a **rule and update map** from controls and incoming events to structure, appearance and rendering. Mark which edits rebuild structure, which merely restyle it, and what Pause or Reset does to an evolving work. Use [Parametric variation](knowledge/parametric-variation.md) (`references/knowledge/parametric-variation.md`) to define control dependencies and produce comparisons that isolate rule changes from seed changes.
2. Implement one rule with simple marks. Have generation return scene data such as positions, connections and stable identities; hand that data to a renderer. Keep a changed palette or viewport from silently rebuilding the data. For a live sketch, distinguish input events from simulation advancement; use an explicit logical update interval where growth needs to be independent of the display refresh rate.
3. Expose only controls that make a meaningful difference to the piece. Add reproducible presets and a way to load a recorded seed and settings. Show a comparison sheet next to the runnable sketch, with ordinary outputs, conspicuous transitions and awkward extremes. If there is an export path, record whether it draws the same scene at a different size or generates a distinct composition for that format.

## Worked example & typical mistakes

Suppose a branching sketch must keep its outline when the human changes the palette. The map assigns branch attachment and length to generation and color to rendering. The first implementation calls the same random generator for both while traversing the tree. Adding a colored tip consumes an extra draw and changes which branch appears next. Instead, generate and store the tree first; resolve each tip's color from a separate seeded source keyed to its branch ID. Now place two renders of the same stored tree side by side with different palettes. Their outlines remain comparable, including when a tip treatment is added. That makes the palette control useful without removing the ability to reroll the structure.

Rerolling until a drawing looks good can hide that many seeds crowd one corner. Show consecutive seeds as well as curated ones. If crowding violates the intended silhouette, revise the growth rule or its bounds rather than silently discarding the outputs.

## Standards, limits & handover

The official p5.js reference distinguishes [`randomSeed()`](https://p5js.org/reference/p5/randomSeed/) from [`noiseSeed()`](https://p5js.org/reference/p5/noiseSeed/); `verify` the installed version and record it with the sketch. These are tool mechanisms, not a guarantee of matching output across renderers. The [WHATWG HTML Living Standard, “Animation frames”](https://html.spec.whatwg.org/multipage/imagebitmap-and-animations.html#animation-frames), defines browser frame callbacks, not a fixed simulation cadence. Seed storage is a project convention; device budgets, dimensions and export format come from the project.

Hand over the executable, run and export instructions, editable controls, and the comparison sheet. Record generator version, seeds and inputs together. Ask which properties must survive rerolls, where surprising outputs belong, and whether live response or export fidelity takes priority. Leave venue behavior for the deployment team to review on the target hardware.
