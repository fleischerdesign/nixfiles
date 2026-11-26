# Design Systems

## When to load & job

Use this for changes that multiple screens or teams will consume. A library distributes reusable parts; a system also says when to use them, who owns the decisions and how consumers adopt changes without losing control of their releases. Deliver a proposed shared contract, a slice of its implementation in real consumers and an adoption note. Use UI as the lead when the change is local and doesn't alter what other consumers depend on.

## Inputs & concepts

Read token definitions, component APIs, usage documentation and versioning conventions. Ask consumer teams for examples in production, upgrade constraints, local overrides and platform differences. Get release ownership from the maintainers. If ownership or rollout policy is unknown, show a proposed change and migration without promising dates.

A **public contract** includes not just an exported name or prop but the meaning consumers rely on: behavior, default values, available slots, and sometimes generated markup or style hooks. A **semantic role** names an intent that should change together across consumers; identical values can express different intents. A **variant** is a named combination with a usage rule. **Composition** lets independently changing parts be assembled without making the system own every combination. A local pattern can stay local even when several screenshots happen to look alike.

## Decisions & procedure

- **Shared role versus local value.** Share a name where roles should track theme changes together, such as surfaces for destructive actions. Keep single-component geometry local until there is a reason for other consumers to depend on it. Public meaning costs maintenance even when it buys consistency.
- **Variant versus composition.** Add a documented variant when the same behavior recurs under stable conditions. Expose a composition point when the parts vary independently. Variants are discoverable, but combining unrelated flags expands the set of behaviors maintainers have to explain.
- **Coordinated change versus compatibility period.** A breaking rename can land in one coordinated release if consumers upgrade together. For independent upgrades, an alias may preserve the old contract while usage docs and release notes teach the replacement. It carries a second name and needs an owner who will decide when to retire it.

1. Build a **consumer contract map**. For each real usage, record the problem, owned input, part that changes, part that must stay stable, owner and release dependency. Compare two consumers with different needs, not two screenshots from one product. Use the differences to decide which parts belong in the shared surface.
2. Sketch the smallest public API and write a usage example and a counterexample. Include defaults, composition points and the treatment of existing instances. If shared values must resolve across themes or releases, use [Design tokens](knowledge/design-tokens.md) (`references/knowledge/design-tokens.md`) to define the mapping without treating matching literals as shared intent.
3. Put the proposed component or token in both consumer contexts. Document the behavior the library supplies and what the product still owns. Use [Accessibility](knowledge/accessibility.md) (`references/knowledge/accessibility.md`) when a shared widget needs semantics, focus or equivalent output; specify where the consumer must supply a name or context the component cannot know.
4. Write the transition in the consumers' syntax: old usage, new usage, any change in appearance or behavior, and who handles the exception. If migration needs different release orders, show a consumer on each side of the compatibility period.

## Worked example & typical mistakes

An illustrative claims queue wants fewer columns; a dispatch queue wants more rows visible but needs every column. In the contract map, the first request changes **which fields are rendered** while the second changes **cell padding and row spacing**. Give claims a product-owned column configuration and dispatch a shared density variant only if that spacing mode has a durable use beyond a single screen. Show a reduced-column table at default density and an all-column table at compact density. These are different states of two independent choices, not two names for a genre of table.

If a shared `compact` flag hides columns, consumers cannot predict what data disappears and someone eventually needs a second flag to restore it. Keep field selection at the product boundary. If the overloaded flag already shipped, preserve its behavior during migration and introduce separately named options rather than aliasing it to a spacing-only variant.

## Standards, limits & handover

[Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html), specification items 1 and 6–8, ties version increments to a declared public API when the project adopts it. The Design Tokens Community Group [Format Module 2025.10](https://www.designtokens.org/tr/2025.10/format/) describes interchange syntax; it is not a W3C Recommendation. `verify` support in the installed generator and consumers. Naming, supported themes and release cadence come from the project, not either specification.

Show the change in real consumers with usage, non-usage, migration and exception ownership. Leave retirement dates to maintainers. Ask which consumers can upgrade together and who decides when a local pattern becomes shared.
