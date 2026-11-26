# Interaction

## When to load & job

Use this when the open question is what happens between an action and its result. Describe what changes, what the person can do next, what happens to focus, and what survives an interruption. UX owns the task sequence; UI owns the screen composition.

## Inputs

Bring the project's component behavior, keyboard conventions, and motion preferences. Get latency, cancellation, retry, and draft semantics from the implementation or service owner. If those are unknown, prototype both the delayed and failed sequences with simulated responses; do not assume a request can safely be repeated.

## Decisions & process

Respond immediately, but distinguish acknowledgment from completion. A reversible change such as starring an item can appear immediately if you can restore the previous state and explain a failure. When duplicate submissions matter or the outcome is uncertain, show that the action is pending and wait before showing success. That is slower to feel complete, but it avoids promising a result the service has not returned.

Separate first load, refreshing existing content, an empty result, and a request error. Keeping old content during refresh preserves context but risks someone acting on stale information; signal that it is updating and limit only actions that depend on fresh data. Preserve entered values on recoverable errors and show what needs changing before retry.

Move focus when the old target is no longer useful, such as when opening a dialog; return it to the trigger on close, or to a logical neighbor if the trigger is gone. Use motion when it explains a state relationship, such as a row expanding into its details. An immediate state change loses that spatial cue but should carry the same information without motion.

## Typical mistakes & examples

Replacing an editable form with a spinner unmounts the focused field and can discard a draft. Keep the form mounted, acknowledge the pending save beside its control, and preserve input if the request fails.

## Deliverables & questions for the human

Show a prototype and annotate action, feedback, focus destination, and retained input along each transition. Ask what cancellation actually stops and which edits may survive dismissal or navigation.
