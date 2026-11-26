# Generative & Creative Coding

## When to load & job

Load this when the artifact is a system that makes a family of outputs: a procedural pattern, a live sketch, or an interactive composition. Build something runnable so the human can explore its behavior; a single striking frame isn't the deliverable.

## Inputs

Bring visual or behavioral references, the properties that should stay recognizable, and the runtime and hardware the work will use. Ask for display dimensions and playback or export constraints. If the target isn't known, name the environment you're prototyping in and leave installation performance open.

## Decisions & process

Separate fixed rules from variation. If a pattern needs a recognizable silhouette, keep its growth grammar fixed and vary spacing or direction within it. If discovery matters more, vary the grammar itself; the range widens, but some outputs may no longer read as a family. Show each rule change against the same set of seeds.

Treat a seed as a way back to a particular output, not as an art-direction control. Record seeds with the parameters and sketch version. Use independent random streams when editing color shouldn't rearrange geometry. A shared stream is simpler and can give pleasing coupled changes, but those changes are harder to direct independently.

If the piece must react live, cap expensive work per frame or reuse computed structure. That keeps interaction responsive at the cost of density or fidelity. If the piece is an export, spend that work offline and give up live exploration. Show how the choice affects the sketch on the available device.

## Typical mistakes & examples

Rerolling until a branching drawing looks good hides the fact that many seeds grow into one dense corner. Show a contact sheet of consecutive seeds alongside a curated selection. If the crowding is unwanted, change the growth rule or its bounds rather than quietly excluding the awkward outputs.

## Deliverables & questions for the human

Share the executable sketch, how to run it, editable parameters, and a seed sheet that includes edge cases. Ask which properties must survive every reroll, where surprising outputs belong, and whether interaction or export fidelity matters more.
