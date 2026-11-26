# Conversational Design

## When to load & job

Load this when people get something done through turns in chat or voice. Design how the system identifies the request, asks for what it needs, and recovers when the exchange goes off track. The chat window's layout is a separate job.

## Inputs

Bring supported intents, examples of how people phrase them, actual service capabilities, channel constraints, and support routing. Get transfer availability and transcript-sharing rules from the service owner. If they're unknown, write a sample exchange with a simulated handoff rather than promising a live one.

## Decisions & process

Use open input when people arrive with varied requests and can describe them in their own words. Offer a short set of choices when only a few actions exist or when a spoken prompt needs to be easy to remember. Choices reduce ambiguity but can hide requests the designer didn't anticipate; show where those requests go.

For ambiguity, weigh an extra turn against the cost of guessing. For a reversible lookup, state the assumption and make it easy to correct. Before a change people can't easily undo, ask a focused question and repeat the specific action. Keep tone plain and specific: say what the system found, not what it supposedly understands.

If the service fails, preserve details already supplied and offer a retry only when it can help. If the outcome is unknown, don't imply the action never happened. Transfer when the conversation needs authority or judgment the system doesn't have. Passing along a short, disclosed summary saves repetition; sharing less protects privacy but may leave the human agent with more questions.

## Typical mistakes & examples

After “Move my appointment,” another “How can I help?” erases the progress made and invites the same wording. If two bookings were found, name the two dates and ask which one to move. If lookup timed out, say that instead and offer a next step without asking the person to restate the intent.

## Deliverables & questions for the human

Show an intent map and annotated transcripts for a routine request, a correction, a service failure, and a handoff. Ask which actions require explicit confirmation, what context may travel with a transfer, and what people should hear when nobody is available.
