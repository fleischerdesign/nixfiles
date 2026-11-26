# Build type specimens by role

## Use when

Choose or implement settings for text people must read, scan or compare. Produce a role specimen with real text in its containers and a settings sheet that carries the decisions into styles.

## Inputs

Collect the manuscript or interface strings, heading hierarchy, dense tables, long labels, language and script list, and the actual print measures or responsive widths. Get licensed font files with their versions, available weights and variants, and intended renderers. Where translations are missing, use marked provisional samples and keep choices about coverage and line breaks open.

## Procedure

1. **Build a specimen matrix.** Give body, display, caption, label and figures distinct rows. Include ordinary and awkward content: paragraphs with punctuation and footnote markers, a wrapping heading, and values with signs, separators and units. Repeat the same samples across family candidates rather than styling each face around its strengths.
2. **Set measure before polishing spacing.** Measure is usable line width; leading in composed type is baseline-to-baseline distance, while CSS line-height controls inline layout, not a universal optical gap. Set body size and width together, then adjust vertical rhythm using actual paragraphs. If a wide paragraph is hard to track, constrain its width before opening up leading; if translated text wraps more, allow height growth before reducing type just to preserve the original breaks.
3. **Choose features by job.** Keep figure width and figure style separate: tabular versus proportional affects advance widths; lining versus oldstyle affects shapes and vertical alignment. Right-align amounts with consistent decimal precision, or use a decimal alignment where precision varies and place units separately. Use `font-variant-numeric: tabular-nums` for web columns where digits need equal advances. Prefer high-level variant properties where available and use explicit OpenType tags for choices they do not express. Record the exact face and feature; a tag does not supply glyphs a font lacks.
4. **Set script and language in context.** Use real strings with joining, marks, punctuation and mixed-direction content where relevant. Set language and direction in the document; pick a fallback that supports the script and compare its line breaks, baseline and mark clearance with the primary face. Do not suppress shaping features to mimic Latin spacing. Write down which role or language uses which family and which settings change on reflow.

## Limits

An attractive Latin specimen cannot speak for another script. A font’s feature list does not guarantee identical rendering in every app. Leave language-sensitive punctuation, shaping and hyphenation decisions to the relevant language and publishing specialists when evidence is missing.

## Worked example

An invoice specimen has amounts `98.20`, `1,008.20` and `−12.75`, with the currency code in a separate column. Right-align all amounts and enable tabular figures only there, so the decimal positions and digit columns align. Keep proportional figures in the payment paragraph so dates do not become loose. In the narrow layout let the translated description wrap while retaining the amount column; choose the label fallback using the translated invoice itself, not an alphabet sample.

## Sources

- Method: Robert Bringhurst, *The Elements of Typographic Style*, horizontal and vertical spacing; `verify` edition and sections.
- Web specification: [W3C CSS Fonts Module Level 4](https://www.w3.org/TR/css-fonts-4/), font matching and `font-variant-numeric`; `verify` publication status for the cited revision.
- Feature definitions: [Microsoft OpenType 1.9.1 registered features](https://learn.microsoft.com/en-us/typography/opentype/spec/featurelist), including `tnum`, `pnum`, `lnum`, and `onum`; features available in a particular font are project inputs.
