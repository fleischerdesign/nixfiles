# Iconography

## When to load & job

Use this when drawing or extending a family of symbols for actions, objects, navigation, or states. Make symbols distinct in use and related as a set. An icon carries a stable meaning beside its neighbors; it isn't a miniature illustration. Deliver a symbol sheet and glyph assets with an in-context control slice, or a labeled study if the intended meanings or production sizes are unresolved. If the open decision is how a control behaves, let interaction design lead.

## Inputs & concepts

Get the current icon library and its source geometry, style variants, target optical sizes, and real neighboring controls. The product owner supplies action names and what each state means; the component owner supplies platform conventions and constraints, including where labels can appear. If the size or meaning is unsettled, label both assumptions in a sample toolbar. Leave library exports until the component owner supplies the missing inputs.

The **view box** defines drawing coordinates; it is not the glyph's visible bounds or the control's activation area. **Keylines** give familiar silhouettes comparable proportions. **Optical alignment** compensates for how shapes appear: curved edges can look smaller than flat ones at the same geometric bounds. An **optical-size variant** is a redrawing for a particular display size, not the same path at another scale. Keep the **glyph** separate from its UI role: the same outline might be decorative beside a label in one place and identify an action on its own in another.

## Decisions & procedure

- **Use shared anchors, then adjust optically.** Reuse the family's stroke weight, caps, corners and alignment anchors. Exact bounds simplify construction; allowing a round outline to extend slightly past a neighboring flat top can make them appear equally tall.
- **Scale one drawing or make size variants.** Reuse one path if its internal gaps and signature features survive the smallest placement. Simplify dense forms for smaller slots; managing more than one path costs maintenance but protects the features that distinguish one symbol from another.
- **Choose metaphors as a set.** Preserve an existing symbol if it already means the same thing here. For related actions, differentiate the silhouettes or show visible labels rather than depending on a tiny badge. Labels take space but replace inference with action language.

1. Make a **meaning-to-glyph sheet**: record the actual label, action or state, nearest confusable neighbors, existing metaphor, target sizes, and intended component. Separate “show current state” from “do this next”; the words on the sheet should make that difference explicit.
2. Sketch candidates beside their neighbors, not as enlarged standalone drawings. Use [Grid systems](knowledge/grid-systems.md) (`references/knowledge/grid-systems.md`) to derive a construction overlay and document optical exceptions. Carry the selected drawing into the smallest actual component.
3. Place the icons in working controls or a labeled toolbar slice. Use [Accessibility](knowledge/accessibility.md) (`references/knowledge/accessibility.md`) to specify how the control expresses its action name and state without depending on the drawing. Keep decorative glyphs out of the control name.
4. Package assets using the library's naming and styling contract. For example, if the icon component paints a monochrome SVG from its text color, use `currentColor` for the painted paths instead of baking in the color shown in the study. Record which variant the component uses at each intended size; don't make consumers infer that from filenames.

## Worked example & typical mistakes

An illustrative file toolbar uses a folder with a plus for “New folder” and a folder with a small arrow for “Move to folder.” At the smallest placement the silhouettes are nearly identical. On the meaning-to-glyph sheet, write that creation produces a new object while moving changes the selected item's location. Keep the established folder-plus for creation; for moving, sketch an item and a directional arrow as the dominant shapes, provided that arrow doesn't already mean “Share” in this product. Pair both with visible verbs. If the narrow toolbar can't fit both labels, put the less frequently needed action in a labeled menu rather than shrinking the differentiating details.

Naming the control “folder with arrow” makes its drawing available but leaves the action unstated. Name the control for what it does, such as “Move to folder.”

## Standards, limits & handover

W3C [SVG 2](https://www.w3.org/TR/2018/CR-SVG2-20181004/coords.html), Candidate Recommendation (4 October 2018), §8.6 defines `viewBox`; set control dimensions separately in the host component. For web controls, W3C [WCAG 2.2](https://www.w3.org/TR/WCAG22/) (Recommendation, 12 December 2024), SC 4.1.2 addresses name, role, and value; SC 2.5.3 applies when a label includes visible text. The icon library’s keylines and stroke treatment are project conventions, not web standards.

Show the symbol sheet, the actual-size controls with their neighbors, and the mapping to meanings and labels. Visual similarity in the sheet cannot establish that users read a metaphor as intended. Ask which controls need to work without visible labels and which established meanings must be preserved.
