# Feedback loops

## Use when

An intervention changes the conditions that shape later decisions. Produce a signed causal-loop diagram and, for any consequential accumulation, a small stock-and-flow sketch. Use them to explain how the immediate effect could fade or reverse, and who experiences the return.

## Inputs

Bring an observed pattern or a proposed rule, actors and their decisions, and a time horizon long enough for responses to come back around. Gather histories of rates and levels, and ask operators what information they actually see when they act. Separate measured series from proposed mechanisms and timings. Without data, draw the mechanism and a qualitative time sketch, not a precise trajectory.

## Procedure

1. Sketch the behavior over time that needs explaining. Name variables that can increase or decrease, such as “open cases” or “time spent on repeat enquiries,” rather than events or vague labels like “support.” Choose which decisions are inside the model and mark external drivers explicitly.
2. Draw a directed link for each specific causal claim. `+` means more of the upstream variable produces more of the downstream variable than otherwise, other things equal; `−` means it produces less. Signs are not judgments or statements about the observed direction of change. Mark the link where a meaningful delay occurs and identify what is delayed: information, a decision or physical movement.
3. Follow a perturbation all the way around a closed path. Label a loop reinforcing if the return amplifies the change and balancing if it counters it. Then trace the response of another actor or resource; an intended balancing loop may compete with a reinforcing one that takes longer to appear. Describe the operating conditions under which each might matter.
4. For quantities that persist, draw **stocks** with inflows and outflows. Name the stock's units and give each flow those units per unit of time. Put decision arrows into rates, not directly into stocks; distinguish an information link from a material transfer. Sketch the stock's direction from the difference between inflow and outflow, even when both rates are falling.

## Limits

Link and loop labels are modeling conventions. A causal map is not evidence of effect size or proof of loop dominance. Quantitative behavior depends on initial stocks, rate equations, delays and evidence about the operating context; leave these as open project inputs rather than supplying plausible-looking constants.

## Worked example

In an illustrative support queue, more open cases prompt teams to increase completions, which drains the stock: a balancing loop. But open cases also lengthen waits; after a delay, longer waits generate follow-up messages. Handling those messages leaves less time to complete cases, so the stock of open cases grows relative to what it would have been: a reinforcing loop. Count follow-ups as workload, not new cases. The model now suggests comparing temporary extra completion capacity with proactive status messages that might interrupt the return path, rather than assuming that either reduces the backlog.

## Sources

- John D. Sterman, [*Business Dynamics*](https://mitmgmtfaculty.mit.edu/jsterman/business-dynamics/) (2000): causal-loop diagrams and stocks and flows; exact chapter references `verify`.
- Robin Hunicke, Marc LeBlanc, and Robert Zubek, “MDA: A Formal Approach to Game Design and Game Research” (2004): rules, emergent play and experienced effects in games; a complementary method, not a stock-and-flow notation.
