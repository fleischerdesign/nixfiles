# Interaction

## When to load & job

Use this when the open question is what happens between an action and its result. Specify what changes, what the person can do next, where focus goes and what survives interruption. UX owns the task sequence; UI owns the screen composition. Deliver a behavior prototype with annotated transitions, or an executable slice when the service and component behavior are known.

## Inputs & concepts

Bring the project's component behavior, input and keyboard conventions, and motion preferences. Ask the implementation or service owner about latency, cancellation, retry, persistence and request identity. If those answers are missing, simulate delayed and failed sequences and label them; neither a simulated retry nor a timeout tells you whether a real request is safe to repeat.

Distinguish an **event** from a **state**: “Save pressed” happened once; “saving” can persist while other events arrive. Acknowledgment means the action was received locally; completion means the intended outcome occurred. Local draft, committed data and the presentation surface may have different lifetimes. Closing an editor does not inherently stop a request. Focus indicates the target of keyboard input, not the same thing as selected content or animation position.

## Decisions & procedure

- **Optimistic versus confirmed feedback.** A reversible star can appear immediately if the interface can restore the prior state and explain failure. For a consequential or potentially duplicate operation, acknowledge immediately but show completion only after confirmation. The wait is visible rather than hidden by a promise.
- **Continuity versus freshness.** Distinguish first load, refresh, empty results and request errors. Retain old content during refresh when it helps orientation, label it as updating and limit only actions that need current data. Preserve editable values on recoverable errors instead of blanking the form.
- **Spatial explanation versus immediate change.** Motion can show how a row becomes a detail pane. If it delays use or is distracting, replace travel with immediate presentation and a stable cue that communicates the same relationship. Move focus because the old target no longer serves the task, not because something moved visually.

1. Write a **behavior contract** beside the initiating control: user intent, stored effect, service events, dismissal meaning and what counts as confirmation. Put unresolved service semantics next to the controls that depend on them. Use [Interaction states](knowledge/interaction-states.md) (`references/knowledge/interaction-states.md`) to expand the contract into a transition table.
2. Build one executable or simulated interaction driven by named events. Keep the parts that hold work mounted through recoverable delays. Stub responses independently of the prototype's visual timing so a fast success, delayed failure and dismissal during a request are distinct experiences.
3. Stage the sequence with keyboard input. Keep focus on the useful target during routine feedback. For a dialog, specify an initial target and a return location, including where to go if the opener disappears. Where changed controls or background feedback affect how someone perceives the result, use [Accessibility](knowledge/accessibility.md) (`references/knowledge/accessibility.md`) for semantics and equivalent output.
4. Add motion after the event sequence works without it. Use [Motion timing](knowledge/motion-timing.md) (`references/knowledge/motion-timing.md`) to specify interruption and reduced-motion equivalents; the destination, available actions and stored result must not depend on an animation finishing.

## Worked example & typical mistakes

In an illustrative board, a person moves a case from “Open” to “Scheduled” in a modal. The service owner says closing can't cancel the pending move. While waiting, the mounted modal retains the selected destination and says “Moving case…”; its dismissal reads “Close,” not “Cancel move.” If the person closes it, focus returns to the row action and the row remains under “Open” while unconfirmed. When confirmation arrives and the row leaves the filtered list, move focus to the next row action only if focus is still on the disappearing row; if the person has moved elsewhere, don't steal it. Convey the move through a status update. The least obvious part is specifying what disappearance does to the *current* focus, not simply using the same fixed return target for every response.

Replacing an editable form with a spinner unmounts the focused field and can discard input. Keep the form mounted, acknowledge pending work beside its control and preserve entered values if the service rejects the change.

## Standards, limits & handover

[WCAG 2.2](https://www.w3.org/TR/WCAG22/) (W3C Recommendation, 12 December 2024), SC 2.4.3 and 4.1.3, concern focus order and programmatically determinable status messages within their scopes. The W3C [ARIA APG Modal Dialog Pattern](https://www.w3.org/WAI/ARIA/apg/patterns/dialog-modal/), “Keyboard Interaction,” gives implementation guidance, not a norm. Motion tokens and persistence are project specifications; the modal above illustrates a service contract and does not establish one.

Show the sequence with action, feedback, focus destination and retained input annotated. Call out simulated responses and ask what dismissal actually stops, which edits survive navigation and what events establish completion.
