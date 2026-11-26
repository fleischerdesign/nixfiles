# Visual Design

## When to load & job

Use this when the same content or identity must work as a visual system across formats. Decide what the eye finds first, how the pieces relate, and which relationships survive a change of medium. Art direction may set the image treatment; here those images have to share space with type, color, and real content.

Build representative layouts and the rules that let another maker adapt them. Use a medium-specific lead if the open question is instead interaction or production artwork.

## Inputs & concepts

Ask the content owner for message priorities, real copy, long names and any required attributions; ask the brand owner for assets, type and color roles, and each channel owner for dimensions, output constraints and viewing conditions. A poster seen across a room and a tile beside eight others offer different opportunities for emphasis. If specifications are missing, label the assumed dimensions and show representative studies rather than final output files.

**Hierarchy** is relative emphasis within an encounter. Size matters, but contrast against surrounding material, isolation, and grouped elements can shift attention without changing point size. **Grouping** attaches related information, such as a date to its event or credit to its image, through alignment and proximity. A **visual role** such as display, metadata or action describes what an element does; the size, weight or color that expresses it can change between formats. **Reflow** is a change in arrangement when the usable space changes, not just reduction of the whole composition.

## Decisions & procedure

- On a poster the image may win the first glance for recognition; on a schedule card, date and venue help people act. Changing the order gives up an identical silhouette across the set.
- Carry type roles rather than literal settings. A wide display face may announce the event from a distance; a narrower face already in the system may keep a long name together on a card, at the cost of some display character.
- A broad accent field ties standalone pieces together. Reserving the accent for the next action makes dense layouts easier to scan but gives them less color presence.

1. Make a **role-and-layout sheet** with rows for the real content and columns for the representative formats. Record first and second reads, grouped content that must move together, and where a role changes emphasis. Mark the conditions where a placement appears without its neighbors.
2. Make low-detail layouts using blocks for grouping and whitespace. Give repeated elements a common edge where it explains their relationship, not just because the edge is available. When the spans or reflow are uncertain, use [Grid systems](knowledge/grid-systems.md) (`references/knowledge/grid-systems.md`) to derive alignment rules from the content.
3. Replace the blocks with type and images. Compare the longest and shortest real headings rather than adjusting only around the nominal one. Use [Type setting](knowledge/type-setting.md) (`references/knowledge/type-setting.md`) for specimens of the roles in their actual containers. Use [Image selection](knowledge/image-selection.md) (`references/knowledge/image-selection.md`) when an asset must play different jobs across placements and a crop could change what it shows.
4. Apply color to the assigned jobs, then show neighboring formats at intended scale. Annotate which relationships repeat and which format warrants a different emphasis, so the next maker knows what to preserve.

## Worked example & typical mistakes

An event series has a launch poster and a narrow schedule card. In the poster sketch, the photo introduces the series before the event title; title and date are grouped below it. In the card sketch, put date and venue immediately beside the title in one reading group, then give the photo its own smaller region. When the longest event name wraps, keep the entire title with its date and let that group grow; don't let the image hold a fixed point between the two lines. Carry the same title-to-metadata contrast and shared starting edge into both formats. A broad accent behind the poster image can become a small accent on the schedule action without having to repaint the whole card.

Shrinking the poster verbatim preserves proportions but leaves the date looking like a footnote. Recompose around the information needed in the narrower encounter and carry the shared relationships, not the original coordinates.

## Standards, limits & handover

Josef Müller-Brockmann’s *Grid Systems in Graphic Design* describes column and modular layout as a method; `verify` edition and section. For web implementations, [CSS Grid Layout Level 1, §4, “Reordering and Accessibility”](https://www.w3.org/TR/2025/CRD-css-grid-1-20250326/#order-accessibility) (W3C Candidate Recommendation Draft, 26 March 2025) explains why visual grid placement is not a substitute for meaningful source order. The role names and alignments are design conventions; format dimensions, licensed fonts and output conditions come from the project or supplier.

Show the layouts at intended viewing sizes and the sheet of shared roles and format-specific changes. If only a mockup exists, the channel implementer supplies a rendering or proof; the study does not show live reflow or physical viewing conditions. Ask what information must survive when space contracts and which format should express the identity most strongly.
