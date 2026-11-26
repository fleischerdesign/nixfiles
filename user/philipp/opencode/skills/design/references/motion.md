# Motion & Animation

## When to load & job

Use this for transitions, animated feedback, and choreography in an interface or graphic. Start with what changed and what the viewer needs to carry from one state to the next. If the question is what the states should be, let interaction design lead.

## Inputs

Bring the state diagram or working flow, the project’s motion tokens, and the events that can interrupt a transition. If timing conventions are missing, use provisional timings in the prototype and label them. Include the host’s reduced-motion preference and any in-product setting that affects playback.

## Decisions & process

- **Continuity or replacement.** When a thumbnail becomes a detail view, carrying its position and shape through the transition can keep the object recognizable. When the old and new views share nothing meaningful, a cut or short dissolve avoids implying a connection, but gives the eye less help relocating.
- **Response or weight.** Start a direct response promptly and let it settle with an ease-out if it needs a visible arrival. A longer acceleration and deceleration can give a large scene change weight, but feels reluctant on a frequently used control. Play the transition under repeated input; reverse or retarget from the current position rather than replaying from the start.
- **Sequence or simultaneity.** Stagger a container and its contents when the order explains their relationship. Reveal together when the user needs to scan or act immediately. For reduced motion, replace travel, zoom, and parallax with a local state change or a cut; preserve the cue without the spatial journey.

## Typical mistakes & examples

A full-screen zoom carries a list item into its detail view. The implementation respects reduced motion for the fade but still runs the full-screen travel, so the viewer loses the sense of place the transition was meant to preserve. Switch directly to the detail view and keep the selected item’s name or thumbnail visible there, so the connection survives without the spatial journey.

## Deliverables & questions for the human

Show an interactive slice with normal and reduced motion, including a rapid reversal. Annotate what starts each transition and when controls become usable. Ask whether users need to track the object across views or resume the task as quickly as possible.
