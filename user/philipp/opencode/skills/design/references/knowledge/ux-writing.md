# UX writing

## Use when

Write the words that help someone act, understand an outcome, or pick up where they left off. Produce a copy sheet tied to the task flow and system states, so labels, messages, and actions can be read in context rather than edited as isolated strings.

## Inputs

Bring the task flow, state table or service blueprint, the terms people use for the task, and the project's voice and component guidance. Ask the implementation owner what each event proves, what work remains in the current view or survives leaving it, and what can be repeated safely. Ask the service owner who takes over at a handoff, what information can travel, and which follow-up commitments they can keep. If an answer is missing, draft against explicit simulated outcomes; don't turn an assumption into a promise.

## Procedure

1. Make a **state-to-copy sheet** with one row per distinct decision or outcome. Record the surface and trigger, what happened, what is known about the result, what work remains and where, and what the user or service can do next. Add the proposed heading, body, and action label in separate columns. Split pending, confirmed, rejected, and unknown outcomes when they call for different wording or actions.
2. For labels, name the field or object in the user's vocabulary. For buttons, name what the control actually does: “Send application” if it sends, “Review application” if it opens a review. Put prerequisites and format instructions beside the relevant field or action before they are needed; don't repeat the label as a hint. Before a consequential action, name the affected item and the consequence rather than asking “Are you sure?”
3. For status, errors, and confirmations, say what happened, what is known, and what the person can do next. Lead with the distinction that changes their decision. Acknowledgment is not completion: “Request received” does not mean “Refund issued.” For a known input error, explain what to change without blame. For an unknown outcome, say so instead of claiming failure or success. Say what work is still available and where, if that affects recovery. Offer a status lookup before a retry that might duplicate the action, and offer only routes that exist.
4. For empty states, distinguish a genuinely empty collection from no matches, loading, and failure to load: “No results match these filters” can lead to “Clear filters,” not “Create item.” A notification read away from the task needs enough context to identify the update and a route back, without exposing sensitive details. For a handoff, say who acts next, which details go with the case, and what the person needs to do, if anything. Distinguish being queued from being accepted. If space is tight, move background detail to the destination; keep the outcome and the next action visible.

## Limits

Copy cannot make a draft durable, a retry safe, or a receiving team available. Record missing behavior or policy next to the affected string and ask its owner to resolve it. Style guidance shapes wording; the project's service behavior determines which claims are true. Read the copy alongside the controls and in the channel where it will appear.

## Worked example

In an illustrative editor, the person selects Save. The editor sends the request but receives no result. The edits are still in the open editor, and the service can look up the attempt without sending it again. The missing reply is known; whether the edits were saved is not. “Save failed” is wrong here because it asserts that the changes did not take effect. “Saved” is equally unsupported.

Use **Save status unknown** as the heading, “Your edits are still in this editor” as the body, and **Check status** as the button. The button looks up the existing attempt, not another save. If the lookup confirms the edits were stored, show “Changes saved.” If it confirms rejection, explain the reason and offer the supported correction. If it returns no result, keep the outcome unknown.

## Sources

- Microsoft Writing Style Guide, [“Writing step-by-step instructions”](https://learn.microsoft.com/en-us/style-guide/procedures-instructions/writing-step-by-step-instructions), “Tips for writing steps”: action wording in instructions (online guide; `verify` revision).
- GOV.UK content and publishing guidance, [“Use clear language”](https://guidance.publishing.service.gov.uk/writing-to-gov-uk-standards/writing-guidelines/clear-language/): plain language and familiar terms (online guidance; `verify` revision).
- Apple Human Interface Guidelines, [“Writing”](https://developer.apple.com/design/human-interface-guidelines/writing), “Best practices”: action-oriented, consistent app copy (online platform guidance; `verify` revision).
- Nielsen Norman Group, [“The 3 I’s of Microcopy”](https://www.nngroup.com/articles/3-is-of-microcopy/) (2025), “Interaction Microcopy”: labels and feedback that support interaction.
