# Design Systems

## When to load & job

Use this for changes that multiple screens or teams will consume. A library distributes reusable parts. A system also explains when to use them, who owns decisions, and how consumers adopt changes without losing control of their releases.

## Inputs

Read the current token definitions, component APIs, usage docs, and versioning conventions. Look at actual consumers and their upgrade constraints, not just examples in the library. If ownership or release policy is unknown, draft the change and a migration example; leave deprecation dates and rollout commitments to the maintainers.

## Decisions & process

Name shared tokens after roles that should change together. If every destructive action should follow theme changes as a group, use a semantic token that resolves to a theme value. If a value expresses a single component's geometry, keep it local until other consumers need the same contract. The shared name buys consistency but commits the system to supporting that meaning.

Add a documented variant when consumers need the same behavior under a stable set of conditions. If the parts need to vary independently, expose composition instead. A variant is easier to discover, but dozens of flags create combinations maintainers must explain. Keep a one-off local when its rationale does not travel.

For a breaking rename, coordinate a single release if consumers move together. For independent releases, consider a temporary alias and show the replacement in usage docs and release notes. The alias makes adoption easier but leaves two names to maintain; name who owns retirement and what evidence will inform it.

## Typical mistakes & examples

Adding a `compact` flag to a table because one product wants fewer columns makes every consumer inherit a misleading density option. Keep column selection in the product. Share a density variant only if it consistently controls row and cell spacing independently of the chosen columns.

## Deliverables & questions for the human

Show the token or API change in real consumers and document when to use it, how to migrate, and who handles exceptions. Ask which consumers can upgrade together and who decides whether a local pattern becomes shared.
