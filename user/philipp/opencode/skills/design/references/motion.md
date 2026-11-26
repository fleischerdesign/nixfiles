# Motion & Animation

## When to load & job

Use this for an executable interface transition, animated feedback, or a choreography prototype for a graphic. Start with what changed and what the viewer needs to carry into the next state. If the question is what states or recovery paths should exist, let interaction design lead. A linear clip can convey a graphic's rhythm; it cannot demonstrate what happens when a person interrupts a transition.

## Inputs & concepts

Bring the working flow or state diagram, real content, the project's motion tokens, events that can supersede an animation, and the host and in-product motion preferences. Ask the interaction owner which event commits the UI change and when focus and controls should move. Ask engineering which properties the renderer can animate without disturbing surrounding layout. Label proposed timings as prototype values when the project has not chosen them.

Separate **logical state** (the destination the interface owes the user), **layout** (the actual bounds in that state), and **presentation** (the currently rendered intermediate position or opacity). A transition bridges presentations; it is not the source of truth for state. **Object continuity** means the same object remains identifiable across different presentations. Shared motion is one way to convey that relationship; repeated content can convey it without travel. **Easing** maps elapsed progress to interpolation progress. It shapes how the object accelerates or settles; it does not determine when a button is usable.

## Decisions & procedure

- **Continuity or replacement.** Carry a recognizable thumbnail into its expanded view when the person must track it. Cut or briefly dissolve between unrelated views to avoid implying a connection, at the cost of less help locating the new content.
- **Response or weight.** Give a direct action a prompt response and, where useful, a visible ease-out settle. A broader acceleration and deceleration can give a scene change weight but makes a frequently used control feel reluctant.
- **Sequence or simultaneity.** Stagger only when order tells the viewer what belongs together or what happens next. Reveal together when elements must be compared or used immediately; you give up the explicit direction of attention.

1. Capture the real endpoint views in the same viewport. Mark persistent objects by identity, not just matching shapes. Identify which can be represented by a visual proxy and which must remain real controls or live content.
2. Make a **transition contract** for one path: record event, destination, persistent object, focus and readiness, presentation layer, and superseding events. Attach a strip for the direction and its reduced-motion alternative. For constructing the beats and assigning usable moments, use [Motion timing](knowledge/motion-timing.md) (`references/knowledge/motion-timing.md`). For mapping a timing choice to the project's reusable roles, use [Design tokens](knowledge/design-tokens.md) (`references/knowledge/design-tokens.md`); keep a one-off study value local unless it expresses a shared intent.
3. Implement one slice with real endpoints. For a shared object moving between layouts, use a noninteractive overlay proxy: measure the start and destination in a common coordinate space, place the proxy over the start, then animate it toward the destination and reveal the real destination. Keep text, hit areas, and focus out of the moving proxy. On an intervening event, let the newest destination own cleanup and redraw from the current presentation rather than queuing another entrance.

## Worked example & typical mistakes

A library preview opens from a tile into a pane. The person closes it while scrolling has shifted the tile. Reversing the original path would land at the old coordinates. Instead, keep the proxy's current viewport rectangle before replacing the animation, measure the tile at its new position, and use that rectangle as the new target. If the tile is no longer rendered, restore the list without a traveling proxy. In reduced motion, cut to the pane and show the same book cover and name there. Changing only the fade while leaving the full-screen zoom intact preserves the very motion the alternative was meant to remove.

## Standards, limits & handover

For web prototypes, W3C [CSS Easing Functions Level 1](https://www.w3.org/TR/css-easing-1/), §2, defines easing functions; [Media Queries Level 5](https://www.w3.org/TR/mediaqueries-5/), §12.1, defines `prefers-reduced-motion`. `verify` the snapshots and runtime support used by the project. These define mechanisms, not suitable durations or what an equivalent cue should be. Ease-out settling is a convention; shipped values belong to the project's motion specification.

Show the same interactive slice with normal and reduced motion, including a rapid reversal. Annotate triggers and when controls become usable. Ask whether tracking the object matters more than resuming the task quickly. The implementation owner can resolve renderer and focus behavior that a standalone prototype cannot establish.
