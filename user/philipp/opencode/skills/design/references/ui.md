# UI (Screens & Components)

## When to load & job

Use this for screens and components. Web and App are aliases when the deliverable is a screen. Decide what should stand out, what belongs together, and how those relationships survive changes in available space. Use UX for the route through the task and Interaction for what happens after an action. Deliver an implemented slice when the project components are available, or an annotated layout study when the implementation constraints are still open.

## Inputs & concepts

Start with the project's design guidance, existing components and semantic tokens for typography, spacing, color and surfaces. Ask the content owner for representative records: long translated labels, crowded lists, absent values and copy from an actual error. Get supported layouts and state descriptions from the product and implementation teams. Label samples when real content is unavailable; final fit and sizing remain provisional.

**Hierarchy** is the order in which the screen makes information and actions available to attention, not just a scale of font sizes. **Grouping** establishes what a label or action applies to. In a repeated list, **shared alignment** makes fields comparable across records; within a record, spacing and headings bind related fields. Distinguish a component's internal layout from the space its parent allocates. A side pane may narrow a list on a wide viewport, so the list's usable width matters more than the device name.

## Decisions & procedure

- **Comparison versus recognition.** Align sender and date when scanning across an inbox matters; make the message preview wider when recognizing the subject matters more. The latter makes fewer messages visible at once. Use the same records and existing density tokens in both studies.
- **Simultaneous context versus space for detail.** Keep list and detail together when decisions depend on both and both remain legible. Move detail to its own surface when they no longer fit. That restores room at the cost of a return trip.
- **Stable frame versus a dedicated next step.** Preserve orientation when a list refreshes or a request fails. If a genuinely empty list has one useful next action, use the vacant space to explain it rather than showing an elaborate frame around nothing.

1. Write a **content-priority overlay** on a wireframe. Mark which fields must be seen together for the task, which are useful per record but not compared, and which can move into detail. Attach each action to the object it changes. Use actual content before allocating columns.
2. Draw wide and narrow versions with the same difficult records. Annotate what wraps, what retains its alignment, and where secondary fields move. For deriving span and reflow rules from these content relationships, use [Grid systems](knowledge/grid-systems.md) (`references/knowledge/grid-systems.md`). Set the composition change where the content stops fitting, using the project's layout conventions.
3. Separate the persistent shell from the replaceable content area. Use [Interaction states](knowledge/interaction-states.md) (`references/knowledge/interaction-states.md`) when a service event determines which content or actions remain. Draw loading, empty and error views beside the populated view, and show focus, hover, active and disabled treatment on actual controls rather than only on a specimen sheet.
4. Translate the overlay to components and layout rules. When visual placement or iconography would leave purpose or order unclear, use [Accessibility](knowledge/accessibility.md) (`references/knowledge/accessibility.md`) to annotate semantics, names and focus. Carry those annotations into the implementation or prototype; they are not implied by appearance.

## Worked example & typical mistakes

An illustrative approvals list shows requester, request title, due date, preview and an action menu. The comparison task is “which request is due next?” The overlay marks title and due date as an inseparable pair: a date without its request is useless. In the wide version the preview gets its own span. In the narrow version, put requester below the title, keep due dates in one aligned column and send the preview to detail. Let the title wrap within its own column; don't move the date down as titles grow. A missing date gets explicit text in that same column so a blank isn't mistaken for a layout gap.

The tempting small-screen conversion is to turn every row into a card with a self-contained stack. Dates then follow variable title and preview heights and stop scanning as a column. Keep the comparison structure in the compact list and use the detail surface for the recognition material.

## Standards, limits & handover

For web work, [WCAG 2.2](https://www.w3.org/TR/WCAG22/) (W3C Recommendation, 12 December 2024), SC 1.4.10 on reflow and SC 2.4.7 on visible focus, supply requirements within their respective scopes. [CSS Grid Layout Level 1 §4](https://www.w3.org/TR/2025/CRD-css-grid-1-20250326/#order-accessibility) (Candidate Recommendation Draft, 26 March 2025) describes why visual reordering is not a substitute for logical source order. The project's actual breakpoints, tokens and supported surfaces are specifications; aligned date columns are a design choice, not a standard.

Show both compositions with the same content and the interactive states relevant to the brief — visible focus, hover, active, disabled, loading, empty and error — including states that do not change the layout. Name missing components or tokens and distinguish simulated states from live behavior. Ask which fields must remain visible together when space runs out, and have the content owner supply the copy or records that could change that decision.
