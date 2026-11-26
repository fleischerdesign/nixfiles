# Derive grids from content and construction

## Use when

Layout elements need shared alignments across pages or widths, or icons need a common construction language. Produce a layout overlay with span and reflow rules, or a scaled icon construction sheet. A layout grid organizes reading and comparison; an icon grid organizes geometry inside a symbol.

## Inputs

Bring real prose, headings, captions, data and image frames; include difficult content, such as the longest caption or widest meaningful figure. Record available widths and margins, writing direction and logical reading order. For icons, use the family’s production sizes, view box, key shapes, stroke and corner conventions, and neighbors in use. Label provisional widths or dimensions when no project system exists.

## Procedure

1. **Find relationships worth aligning.** Mark the edges and baselines that help a reader connect related things: title to body, figure to caption, and repeated labels to values. Measure representative body text and modules at actual type settings. Use the widths they need to sketch spans before choosing a column count. Compare a simple main-and-side split with a modular grid if figures need several useful spans.
2. **Turn the sketch into a grid.** Draw margins, tracks and gutters on top of the composition. For equal tracks, divide the inside width after subtracting the gutters by the track count; a multi-track span includes its internal gutters. Use different track widths when the content roles are asymmetric. If a fixed-height row fights variable captions, align their starts and let their height follow the copy. Name the edges and baseline relationships that repeat instead of preserving every line on the overlay.
3. **Write the reflow rule.** When minimum usable spans plus gutters no longer fit, stack the modules in logical order or change their spans. Keep captions with figures. On the web, establish the meaningful source order before declaring grid areas; visual placement does not change the default order of speech or sequential navigation.
4. **For icons, start with family anchors.** On a separate construction sheet mark the drawing area, center axes, key silhouettes and common stroke centers. Place junctions and gaps to preserve the distinguishing feature at the target size. Compare adjacent icons at that size; let curves overshoot an anchor optically or draw a simpler small variant if literal alignment closes a counter. Record the exception on the construction sheet.

## Limits

A grid is a convention for the artifact, not a mandate for a particular track count or spacing multiple. An icon view box does not define the activation area of its control. The overlay explains alignments; the human judges how they read in context.

## Worked example

An illustrative field guide has prose, species images and identification captions. Early sketches place captions in a narrow side track, but the longest caption wraps so much that it appears attached to the next image. Treat image and caption as one module spanning both side tracks. At narrower widths put each module immediately after its corresponding paragraph in the source and allow it to fill the column. The species name stays aligned with the image edge without the rest of the caption dictating the prose measure.

## Sources

- Method: Josef Müller-Brockmann, *Grid Systems in Graphic Design*, column and modular layout; `verify` edition and section.
- Web specification: [W3C CSS Grid Layout Level 1, §4 “Reordering and Accessibility”](https://www.w3.org/TR/2025/CRD-css-grid-1-20250326/#order-accessibility), Candidate Recommendation Draft, 26 March 2025.
- Example convention: [Material Design 2, “System icons”](https://m2.material.io/design/iconography/system-icons.html), construction grid and keylines for that family, not universal dimensions.
