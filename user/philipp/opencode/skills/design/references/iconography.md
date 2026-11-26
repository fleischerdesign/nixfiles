# Iconography

## When to load & job

Use this when drawing or extending a family of symbols for actions, objects, navigation, or states. The job is to make symbols distinct in use and related as a set. An icon has to carry a stable meaning beside its neighbors; it isn't a miniature illustration.

## Inputs

Start with the existing library, its grid and stroke conventions, target optical sizes, and the actions or states the symbols represent. Bring the actual interface labels and platform conventions. If sizes or meanings are undecided, show a symbol study in a sample toolbar with the assumed size and label each provisional meaning; leave library exports until those inputs are known.

## Decisions & process

- **Set the grid, then adjust by eye.** Reuse the family's anchors, stroke weight, caps, and corner treatment. Allow a round outline to extend slightly past an adjacent flat edge when both need to appear the same height. Exact grid alignment makes construction simpler, but identical bounds can make different silhouettes look uneven.
- **Draw for the optical size.** Reuse one drawing if its internal gaps and distinguishing features survive at the smallest size. For dense symbols, draw a small variant with fewer details and more space between strokes. You give up one universal asset but keep the feature that separates it from its neighbors.
- **Choose metaphors as a family.** Prefer an established symbol when it means the same thing in the current product. When adjacent actions have related meanings, differentiate their silhouettes or pair them with visible labels rather than relying on a tiny badge. Visible labels take room but spare readers from having to infer the difference.

## Typical mistakes & examples

Two unlabeled folder icons differ only by a small plus or arrow; in a compact toolbar, “New folder” and “Move to folder” start to look interchangeable. Give the controls visible labels and distinguish the action shapes. For any icon-only control, give the control a programmatic name that describes the action, not the drawing; keep decorative glyphs out of that name.

## Deliverables & questions for the human

Show the symbol sheet, actual-size controls with neighboring icons, and the mapping from glyphs to meanings and labels. Ask: Which controls need to work without visible labels? Which existing meaning must be preserved even if a new metaphor looks clearer in isolation?
