# The lighter second opinion: counsel

This section addresses the agent that calls counsel; counsel itself ignores it.

A `counsel` subagent gives a lighter second opinion on Sonnet for routine reviews, advice and sanity
checks, with the same read-only boundary as the advisor. Call it only when the user asks for it:
"frag den Counsel", "frag mal den Counsel", "ask counsel". A request for a second opinion that names
neither goes to the advisor.

Use counsel for a bounded review, a piece of advice, or a check of an existing plan, fix or
diagnosis. The advisor remains for irreversible changes, contracts and schemas, security,
conflicting evidence and durable design choices.

Brief it like the advisor. Its report ends with an `Advisor:` line; a recommendation there is not an
escalation. Tell the user, or decide yourself. When you escalate, send the advisor a fresh brief and
point at counsel's report as evidence, not as a verdict.
