# The lighter second opinion: Counselor

This section addresses the agent that calls Counselor; Counselor itself ignores it.

A `Counselor` subagent gives a lighter second opinion on Sonnet for routine reviews, advice and
sanity checks, with the same read-only boundary as the Advisor. Call it only when the user asks for
it: "frag den Counselor", "frag den Counsel", "ask Counselor". A request for a second opinion that
names neither goes to the Advisor.

Use Counselor for a bounded review, a piece of advice, or a check of an existing plan, fix or
diagnosis. The Advisor remains for irreversible changes, contracts and schemas, security,
conflicting evidence and durable design choices.

Brief it like the Advisor. Its report ends with an `Advisor:` line; a recommendation there is not an
escalation. Tell the user, or decide yourself. When you escalate, send the Advisor a fresh brief and
point at Counselor's report as evidence, not as a verdict.
