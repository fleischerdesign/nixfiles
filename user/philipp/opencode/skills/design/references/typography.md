# Typography

## When to load & job

Lead with Typography when selecting and setting faces for an interface, document, or artwork. Deliver a specimen built with project content and a settings sheet or implementation that gives each text role a distinct reading job. The design might need passages people can follow line by line, labels they can pick out in a crowd, or numbers they can compare without rereading the column. Use Type Design when the requested change is to glyph outlines, spacing inside the font or font behavior itself; use Editorial when the main decision is across pages.

## Inputs & concepts

Gather the existing type rules, actual licensed font files and weights, and the intended renderers. Ask content and localization owners for real copy across roles, including translations, mixed scripts, numbers and units. Get the actual available widths inside their containers, not just the viewport or page width. Use labeled substitutes for missing fonts or translations; coverage and line breaks remain provisional.

Distinguish **size**, the scaling of the em, from apparent size: x-height, proportions and weight can make two faces at the same size look unequal. **Measure** is the usable line width. **Tracking** changes overall letter spacing; **kerning** adjusts the spacing of particular combinations. **Leading** relates to baseline separation; CSS line-height participates in computing line boxes, which may also have to accommodate runs from different fonts. A **fallback** can be picked for missing glyphs within a line as well as for an unavailable face. Similar visual size does not imply similar character advances or line metrics.

## Decisions & procedure

- **One family or a pair.** A single family can connect body, labels and figures. A contrasting display face earns its place when the title needs a voice the body family cannot supply, but adds metrics and fallback behavior to maintain. Use identical content in both versions.
- **Measure or vertical space.** If readers lose the next line, try a narrower body column before creating a much looser paragraph. The narrower column uses more height. For a tight heading, compare a natural wrap and a smaller or quieter style before using tracking to preserve an arbitrary break.
- **Stylistic or metric continuity.** Start with script coverage. Then choose between a fallback that occupies similar space and one whose shapes better match the primary face. A flexible layout can make the latter practical.

1. Build a **role-by-container specimen**. Label each sample with its job, available width and language; include the narrowest ordinary case and a dense case such as a price table or caption with credits. Use [Type setting](knowledge/type-setting.md) (`references/knowledge/type-setting.md`) to derive the settings from these specimens rather than from an isolated alphabet.
2. Establish body setting before tuning the hierarchy. Use [Grid systems](knowledge/grid-systems.md) (`references/knowledge/grid-systems.md`) to connect workable text measures and alignment edges to actual layout spans. Where the slot shrinks, decide which role wraps, which module stacks and which figures must stay aligned; do not shrink every role together.
3. Put the specimens back into the intended templates. Encode the roles in styles, preserve language and direction in the document, and record face, weight, spacing, features, wrapping and fallback. Include a version that uses the fallback in the narrow container so the human sees the effect without imagining it.

## Worked example & typical mistakes

A stock list has a long translated item name beside quantities such as `9`, `91` and `111`. The specimen shows that the fallback wraps the name one line earlier, but letting that column grow vertically preserves the quantity column. Assign figure settings to the quantity style alone and align its entries to the right; keep proportional figures in the description. Where a unit was previously part of the quantity, move it to the column heading if all values share the unit. That leaves the figure alignment intact even when the name wraps.

Right-aligning proportional digits can make the outside edge tidy while leaving place values uneven inside the column. Use tabular figures for this comparison; don't apply them to all text just because the table needs them.

## Standards, limits & handover

[W3C CSS Fonts Module Level 4](https://www.w3.org/TR/css-fonts-4/), “Font Matching Algorithm” and `font-variant-numeric`, explains matching and feature selection; `verify` publication status for the cited revision. The [OpenType 1.9.1 feature registry](https://learn.microsoft.com/en-us/typography/opentype/spec/featurelist) defines tags such as `tnum`; it does not require every family to supply the feature. Right-aligning a quantity column is a convention. Required languages, licensed files and rendering targets are project inputs.

Show representative narrow and wide specimens, the role settings and fallback behavior. Ask which languages must ship and which containers truly need compactness. Have language owners review script-specific setting; selecting a face is not a claim about coverage or behavior in applications you did not use.
