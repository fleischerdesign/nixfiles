# Interaction states

## Use when

Specify what happens after an event, including when the result is delayed or uncertain. Produce a state table that connects service outcomes to visible feedback, available actions, retained work, and focus. Use it beside the screens rather than drawing every combination as a new screen.

## Inputs

Bring the task flow, controls, keyboard behavior, draft policy, service events and outcome meanings. Ask the service owner what cancellation stops, how repeat requests are handled, and how to distinguish rejection from an unknown outcome. Use simulated events for unsettled behavior and mark assumptions; a prototype retry does not establish that a real request is safe to repeat.

## Procedure

1. Separate states from events. “Saving” can persist; “Save pressed” and “Save confirmed” are events. Distinguish the state of the work from the state of its surface: an editor can close while a save is still pending, if the project allows it. Note which changes are local and which depend on a response.
2. Make one row per meaningful transition. Use columns for current state, event and condition, next state, visible or programmatic feedback and actions, retained data, and focus. Write competing outcomes separately. If response order can differ from request order, name which response still owns the current view; a stale response must not overwrite a newer result.
3. Design pending work as its own situation. Acknowledge the action without announcing completion. Keep unrelated actions available when their use cannot interfere. Decide what happens on repeated input and navigation. Name cancellation “Stop waiting” or “Close” if it cannot stop server work, and provide a route back to resolve an unknown outcome before offering a potentially duplicate operation.
4. Record where focus goes and why. Keep it on the current control when it still serves the task; use a status message for an update that doesn't require moving focus. For a modal, choose a useful initial target and a return target, including a fallback if the opener disappears. Pair each recovery action with the input it retains, the message it needs, and the next state it enters.

## Limits

The table specifies behavior, not latency or persistence guarantees. A product decision about dismissal, a service guarantee about cancellation, and the APG modal pattern are different inputs. Use the modal pattern for an implemented modal, not for background work that need not block interaction.

## Worked example

An illustrative rename editor uses these transitions. The service owner in this example supplies a way to look up the operation after a lost response.

| Current state | Event → next state | Feedback, actions, and retained work | Focus |
| --- | --- | --- | --- |
| Editing | Save pressed → Pending | “Saving name…”; keep draft and prevent another send. | Stay on Save; configuration keeps it focusable during pending. |
| Pending | Name rejected → Editing | Explain the naming constraint; keep entered text for correction. | Move to Name, associated with its error. |
| Pending | Response lost → Outcome unknown | Keep draft; offer “Find save status,” not another Save. | Move to “Find save status” if it replaces the focused control. |
| Pending or outcome unknown | Service confirms rename → Closed | Update the row label and expose the completion message. | Return to the row's rename control, or its logical neighbor. |

## Sources

- David Harel, [“Statecharts: A Visual Formalism for Complex Systems”](https://doi.org/10.1016/0167-6423(87)90035-9) (1987): original method for events, transitions, hierarchy, and concurrent regions. The table is a simplified working representation.
- W3C ARIA APG, [Dialog (Modal) Pattern](https://www.w3.org/WAI/ARIA/apg/patterns/dialog-modal/), “Keyboard Interaction”: implementation guidance on entry, containment and return of focus, not a normative standard.
