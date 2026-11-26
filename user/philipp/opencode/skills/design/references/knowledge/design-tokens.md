# Design tokens

## Use when

Derive shared values from design roles and carry them across themes or releases. Produce a token map from source values to consuming components and a migration note. This is about the meaning and stability of a name, not making every repeated literal public.

## Inputs

Bring existing token sources, theme definitions, component usages, supported platforms and value types, and the generators that ship the values. Identify who owns the palette, semantic roles, component API, and releases. Ask how consumers select a theme and whether they release together. If that information is missing, sketch the role map and example resolutions without committing to precedence, fallback behavior, or retirement dates.

## Procedure

1. Inventory uses by intent. Two equal values might describe unrelated roles; two different values might express the same role in different themes. Put reusable raw choices in **primitives**, such as a palette step. Put cross-component intent in **semantic aliases**, such as text for danger. Add a **component role** when a named slot needs a separate contract; otherwise let the component consume the semantic token directly. These are naming conventions, not prescribed layers of the format.
2. Draw one path per use: component slot → semantic alias → primitive, omitting a layer when it adds no meaning. Record type and units, owner, and whether consumers can use the name directly. Keep reference direction clear: primitives do not depend on component roles. Use compatible types for targets and avoid circular references.
3. Make a resolution matrix with roles as rows and supported contexts as columns. List the selected primitive and resulting value in each cell. A light and dark theme can resolve the same semantic role to different palette steps without forcing components to branch. If a brand and a theme both set a role, write which contribution wins, how contexts combine, and what happens when a context is omitted. Use the project's resolver and release rules, rather than relying on file ordering by habit.
4. Treat published names, types, and meanings as consumer contracts. List old and new names, affected usages, and what changes on screen. Keep a deprecated alias when consumers upgrade separately and the old meaning still holds; if the meaning changes, give it a new name instead of disguising the change with an alias. Name the release owner and document the migration in the consumer's syntax.

## Limits

Community specifications describe interchange and resolution; they do not prescribe your palette, release calendar, or generator support. A resolved name does not establish how a color pair reads or how a platform applies it. Show actual component pairs in context for human review.

## Worked example

In an illustrative map, `button.danger.label` points to `text.on-danger` while `button.danger.fill` points to `surface.danger`. Light and dark themes resolve the text and surface roles to their own primitive pairs. An alert's `text.danger` remains separate: it sits on the normal surface, so matching a button's label by coincidence in one theme should not bind the roles. If an old `button.delete.label` export carries the same role, document its temporary alias to `button.danger.label` and show an old and new component reference without changing the rendered pair.

## Sources

- Design Tokens Community Group [Format Module 2025.10](https://www.designtokens.org/tr/2025.10/format/), type and reference resolution, and [Resolver Module 2025.10](https://www.designtokens.org/tr/2025.10/resolver/), modifiers, contexts, and resolution order. These are community specifications, not W3C Recommendations; `verify` support in the project's toolchain.
