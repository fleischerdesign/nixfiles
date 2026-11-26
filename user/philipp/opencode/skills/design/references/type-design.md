# Type Design

## When to load & job

Use this when the deliverable changes the font itself: variation axes, glyph behavior, spacing, kerning, or OpenType features. The role is Prototype: build a small experimental font or a specimen that answers a specific question. Full typeface production and release belong to a type designer or font engineer.

## Inputs

Get editable sources, modification rights, the intended glyph subset and scripts, target sizes and applications, and the existing master and feature definitions. If sources or rights are missing, use an explicitly licensed sample font to demonstrate the mechanism; changes to the project font must wait.

## Decisions & process

- **Axis or named styles.** Use a variable axis when the application needs meaningful intermediate values, such as a width adjustment for headlines. Named styles are simpler if the design only needs a few distinct voices. A continuous axis needs compatible outlines across masters and may need an intermediate master where the drawing changes character. Show the extremes and middle on the same string.
- **Sidebearings before kerning.** Adjust sidebearings when a glyph leaves a hole next to many neighbors; that changes its spacing everywhere. Use class kerning for recurring shape pairs and a pair exception when one combination needs a different correction. Compare repeated control strings and words across weights so a fix for one headline doesn’t dictate the alphabet’s rhythm.
- **Default substitution or opt-in.** Use an OpenType feature such as `locl` for forms appropriate to the text’s tagged language. Keep discretionary alternates opt-in when they change the tone rather than the language. That preserves predictable default text but means the application has to expose the alternate.

## Typical mistakes & examples

The light and bold masters look fine separately, but reversed contour order makes a counter collapse midway through the axis. Align contour and point correspondence before redrawing the middle; show the troublesome instance in text as well as in outline.

## Deliverables & questions for the human

Provide the prototype source, a specimen with axis coordinates or feature toggles, and the glyphs and environments represented. Ask which intermediate values and apps matter. A font engineer takes the prototype into full character coverage, broader rendering proofs, and release work.
