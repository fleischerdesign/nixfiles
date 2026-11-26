# UI (Screens & Components)

## When to load & job

Use this for screens and components. Web and App are aliases when the deliverable is a screen. Decide what should stand out, what belongs together, and how that composition changes with available space. Use UX for the route through the task and Interaction for what happens after an action.

## Inputs

Start with the project's design guidance, components, and semantic tokens for type, spacing, color, and surfaces. Bring representative content, including long labels and crowded lists, plus the supported layouts and screen states. If constraints or content are missing, show a layout study with labeled samples and assumptions; leave final sizing and copy fit open.

## Decisions & process

Start with what people need to see together. For an inbox where people compare senders and dates, aligned rows make scanning easier at the cost of room for previews. Where recognizing the message matters more than comparing fields, give the preview space and accept fewer items per screen. Show both with the same content and existing density tokens.

When a detail pane supports decisions about a list, keep both visible where they fit. On narrow screens, put the detail on its own surface rather than squeezing both panes; that costs an extra trip back to the list. Set the breakpoint where the content stops fitting, within the project's layout conventions.

Keep the frame stable when people need to stay oriented during loading or errors. If a genuinely empty view has one useful next action, give it the space the list would occupy instead. That makes the action clearer but puts less of the normal layout on display.

Design the interactive states as part of the composition, not as a later skin: visible keyboard focus on every control, hover and active feedback, disabled and loading states, empty and error views. A state that exists in code but not in the screen the human reviews is not designed yet.

## Typical mistakes & examples

Turning each table row into a card at small widths breaks the shared alignment people use to compare due dates. Keep the decisive fields aligned in a compact list and put secondary fields in the detail view.

## Deliverables & questions for the human

Show wide and narrow compositions with the same content, plus the interactive states relevant to the brief — visible focus, hover, active, disabled, loading, empty and error — even when they do not change the layout. Name any gap in the project components or tokens. Ask which fields must remain visible together when space runs out.
