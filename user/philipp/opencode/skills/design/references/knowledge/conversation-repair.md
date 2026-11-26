# Conversation repair

## Use when

A conversational prototype must recover when a reference is unclear, input is lost, or a supported intent cannot be completed. Produce annotated sample dialogs and a small repair-state table, including what the conversation retains or transfers so the person does not have to begin again.

## Inputs

Bring representative utterances, the supported task model, candidate referents and which details the channel can display or speak safely. Gather observed misunderstandings if available, the system's actual error signals, justifiable confirmations, and what a receiving role can access. Distinguish reported behavior from scripted assumptions. If the handoff channel is undecided, show a proposed transfer summary and a fallback when it cannot be sent.

## Procedure

1. Mark the trouble source in the transcript. Separate silence or unrecognized input from an ambiguous referent, a missing detail, a misunderstood intent and an unavailable action. Name what remains usable from prior turns; preserving a chosen date may let you clarify only the location.
2. Draft the smallest prompt that lets the person repair the trouble. For plausible referents, offer distinguishing labels or ask for a distinguishing feature. For no input, restate what the system is waiting for and surface another input mode if available. For an unsupported action, explain the limit and offer a real next path rather than repeatedly rewording the same question. If an action was sent but its result is unknown, say so and seek its status before suggesting a repeat.
3. Annotate each dialog with the **repair state**: known details, pending question, acceptable paraphrases and correction moves, proposed action, and branch on repeated difficulty. Let the person correct a detail without losing unrelated choices. When a wrong guess has consequences, state what would happen and ask before committing; a low-consequence, reversible selection can instead be shown with a clear correction route.
4. Write the transfer as a turn the person can understand, plus a receiver-facing record with goal, confirmed facts, unresolved point and attempted actions. Share only the context authorized by the service, and show who acts next. If the transfer is unavailable, offer a recoverable next step or a summary the person can take elsewhere.

## Limits

Conversation-analysis findings describe interaction patterns; they do not prescribe retry counts or prove a scripted dialog will work. Retry policy, retention and handoff permissions are project specifications. Platform guidance applies to its supported channels; the prototype cannot promise human availability or access to transferred context.

## Worked example

Illustrative dialog:

- **Person:** “Move that to Friday.”
- **Assistant:** “The delivery or the pickup?” *Keeps Friday; neither booking has changed.*
- **Person:** “Pickup. Actually, Saturday.”
- **Assistant:** “Saturday pickup isn't available here. I can connect you to scheduling about other pickup times. Shall I send them that request?”
- **Receiver note after agreement:** “Wants to move pickup to Saturday. Saturday unavailable in self-service. No change made. Next: offer available times.”

The sample makes the correction and the pending action visible. A transcript dump would bury both under obsolete references to Friday and delivery.

## Sources

- Emanuel A. Schegloff, Gail Jefferson, and Harvey Sacks, [“The Preference for Self-Correction in the Organization of Repair in Conversation”](https://doi.org/10.2307/413107), *Language* (1977): trouble sources and opportunities for self-repair in human conversation.
- Google Conversation Design, “Errors”: historical no-input and no-match examples for Conversational Actions, a retired platform; archived documentation version `verify`. Do not use it to infer current platform behavior.
