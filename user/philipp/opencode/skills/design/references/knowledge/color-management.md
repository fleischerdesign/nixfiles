# Map source color to its destination

## Use when

Assets from different sources must agree in a composite, review image or printed object. Produce a color route table and a proof brief that distinguish how pixels are interpreted, how they are transformed, and how the result is viewed.

## Inputs

Gather original files and embedded profiles, camera or render encoding notes, working space, and one specification per output. A screen or video delivery may name primaries, transfer function and viewing transform; a print job may name a profile or printing characterization, substrate, inks, and finishing. Record provenance for untagged files. An unlabeled RGB triplet supplies values, not their color meaning; mark any proposed interpretation provisional.

## Procedure

1. **Inventory the encodings.** Give each asset a row: source encoding and evidence, working representation, transform, destination, and owner of that transform. Assign a source profile only to describe what the existing numbers already mean; converting changes the numbers to represent color in a different space. If two source interpretations are plausible, show both against a known reference rather than assigning the one that looks nicest.
2. **Separate working, viewing and delivery.** In an ICC workflow, use source and destination profiles and choose a rendering intent suited to the material. For example, compare media-relative and perceptual conversions where saturated photographs lose separation; what perceptual mapping does depends on the profiles. Preserve a tagged master. In an OpenColorIO workflow, record the configuration, input color space and display/view pair. Keep a scene-referred master distinct from a rendered review copy; bake a viewing transform only where the delivery calls for it.
3. **Name the print condition and ink plan.** A PDF output intent describes the intended printing condition, not a command to convert every object. Put conversion responsibility in the brief. For a process job, specify colors in the supplied output condition, not generic CMYK percentages. If a brand color or finish needs a separate ink or coating, use the converter’s named spot separation and record its preview alternate separately. A similar screen swatch does not create or replace a plate.
4. **Brief the proof around the decision.** List the destination condition, viewing setup and the patches or image areas to compare, such as shadow texture or a solid next to a photograph. For substrate-dependent spots and coatings, request an ink drawdown on the intended stock or a physical production-style sample, as appropriate to the supplier.

## Limits

A soft proof depends on the display, profile and viewing conditions. Neither a monitor nor an ordinary process proof represents every spot ink, metallic finish or substrate interaction. An OCIO display/view transform is not the PDF mechanism for declaring a press condition.

## Worked example

A carton combines a tagged portrait with a vivid orange brand block. The converter offers a process-only run or process plus a custom orange. Make one proof view with the orange mapped into the supplied process condition and another layout with the block as a named spot. Keep the same portrait conversion in both. Request the orange on the intended board beside the process swatch; the decision now concerns the visible difference and extra ink, not two arbitrary monitor oranges.

## Sources

- Norm: [ICC.1:2022](https://archive.color.org/specification/ICC.1-2022-05.pdf), §6, profile connection space, rendering intents and device encoding; `verify` amendments for the implementation in use.
- Tool: OpenColorIO official documentation, [Authoring Configurations](https://opencolorio.readthedocs.io/en/latest/guides/authoring/authoring.html) and [Displays & Views](https://opencolorio.readthedocs.io/en/latest/guides/authoring/displays_views.html); `verify` config and runtime versions.
- Project specification: supplier or delivery owner names the destination condition, inks and proof method. The orange comparison is illustrative.
