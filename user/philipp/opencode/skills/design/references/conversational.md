# Conversational Design

## When to load & job

Lead here when a task is accomplished through turns in chat or voice. Make an intent map and an annotated dialog prototype that show how the system identifies a request, obtains only the details it needs, makes commitments, and recovers. Use UI design for the chat window itself, or service design if the main problem is restructuring what staff and systems can deliver. Simulated service outcomes are enough to explore the dialog without making real changes.

## Inputs & concepts

Bring representative utterances, the task and operation catalog, channel capabilities, and support routing. Ask engineering what the service can distinguish after an operation starts and whether an operation reference can recover its result. Ask the owner which transfers are staffed and what context may travel; ask the channel owner what can be displayed or spoken in the intended setting. Use fictional records in role-play; treat hypothetical phrases as examples, not observed language. If availability or sharing is unknown, script the transfer as a simulation.

An **intent** is the task the person means to accomplish, not a phrase to match. A **referent** is the particular record or object they mean. **Slots** are task details such as date or location; distinguish a value the person confirmed from one merely inferred. **Turn context** is the working memory of the exchange, whereas **execution state** belongs to the underlying operation and may outlive the conversation. Getting agreement to make a change is different from knowing the change occurred.

## Decisions & procedure

- **Open input versus choices.** Open with free input for varied requests people can name. Use a short menu when the service can only do a few things or listeners cannot keep a long prompt in mind. Give out-of-menu requests a route; a menu is not a complete account of user needs.
- **Extra turn versus wrong action.** For a reversible lookup, state the assumption and make it correctable. For a costly change, name the target and consequence before acting. Keep the language concrete: “I found two bookings” says more than “I understand.”
- **Retry versus transfer.** Retry only where another attempt can help. Preserve known details and distinguish an unknown operation outcome from a known rejection. Transfer work that needs authority or judgment. An authorized summary saves repetition; sending less protects privacy but can leave more work for the recipient.

1. Draft an **intent-to-operation map**. List the user goal, candidate phrases, required record and details, the operation actually offered, and the evidence that permits a completion message. Split a single phrase across different intents when the consequence differs. Include an unsupported branch rather than quietly broadening the service.
2. Write one routine dialog and annotate each assistant turn with what changed: accepted detail, pending choice, authorized command, or service outcome. In voice, identify choices by short distinguishing labels; in chat, keep the prompt and available choices readable together. Use [Conversation repair](knowledge/conversation-repair.md) (`references/knowledge/conversation-repair.md`) to turn real ambiguity or misunderstanding into alternate turns without losing context.
3. Wire the transcript to scripted backend outcomes or use a facilitator to drive the branches. Use [Interaction states](knowledge/interaction-states.md) (`references/knowledge/interaction-states.md`) to model pending, rejected and unknown operations separately from the dialog. Use [Service blueprint](knowledge/service-blueprint.md) (`references/knowledge/service-blueprint.md`) to translate a transfer promise into an accountable handoff, including the unavailable branch.

## Worked example & typical mistakes

In a fictional booking service, the person says, “Move my appointment to Friday.” The intent map binds Friday as the requested day but leaves appointment identity open. After “The dental visit on Tuesday or the fitting on Wednesday?” and “The fitting,” show the exact available Friday time and ask before sending the change. Now model the least obvious branch: the send times out *after* the person agrees. The annotation retains the fitting, authorized time, and operation reference; it does not return to choosing a date. The next turn is “I sent the request, but I don’t yet know whether the fitting moved. I can look up its status.” This wording assumes the example service supports a status lookup. If it does not, show the actual route to a person or record that can resolve the uncertainty.

A generic “How can I help?” after a lookup timeout erases progress and invites the same utterance. Keep the request, explain that lookup did not return, and offer a next step suited to a failed lookup, not a second unexamined booking change.

## Standards, limits & handover

For web chat, [WCAG 2.2](https://www.w3.org/TR/WCAG22/) §3.3.1 concerns identifying automatically detected input errors in text, and §4.1.3 covers status messages in markup-based content without moving focus. Neither specifies dialog wording or retry counts. For voice prototypes, [W3C SSML 1.1](https://www.w3.org/TR/speech-synthesis11/) §3.1.10 defines the `phoneme` element for specifying pronunciation where ambiguous names affect a choice; `verify` support in the synthesis engine before relying on it. Concise spoken options are a convention; retention, confirmation and transfer rules are project specifications.

Hand over the intent map and annotated routine, correction, service-failure and handoff dialogs in the target channel or a labeled simulation. Ask which actions need explicit agreement, what context can be transferred, and what people should hear when nobody is available.
