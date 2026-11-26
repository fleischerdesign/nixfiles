# Information Architecture

## When to load & job

Use this to organize content and destinations so people can predict where to look. Work on categories, relationships, navigation and labels before drawing visual treatments. UX takes over when the main question is how someone completes a task at a destination. Deliver a text-first tree, a content-to-destination map and representative routes through navigation, search and direct entry.

## Inputs & concepts

Start with a content inventory, current navigation and URLs, known destinations, and vocabulary from search, support and real records. Ask publishers who owns each item, which records represent distinct services and which inbound links must keep working. A search term suggests intent but does not prove which destination satisfied it. Where there is no evidence about mental models, label groupings and vocabulary as hypotheses and show where existing items would land.

A **taxonomy** assigns terms to content; a **navigation hierarchy** exposes selected relationships as routes. They need not be identical. A **canonical home** is the destination's maintained identity and place in the hierarchy. **Alternate entrances** can express different intents without creating copies. A **facet** is an independently described attribute that lets someone narrow a set, rather than a branch that owns a subset. Distinguish a content owner's administrative label from the public term people can recognize before choosing.

## Decisions & procedure

- **Task-first versus object-first siblings.** “Replace a card” gives known intent a direct entry; “Cards” lets people explore related options before deciding. Compare text-only trees with the same destinations so wording and visual emphasis do not mask a different first fork.
- **One home versus multiple entrances.** Give a destination with one owner a maintained home and link to it from alternate contexts. The visitor's route may differ from the breadcrumb, which describes the destination's position, not their history. When several overlapping attributes apply to many items, use facets if the metadata supports them instead of repeating near-identical branches.
- **Domain precision versus recognition.** A specialist term can separate nearby categories more precisely; plain language may be easier to identify but less exact. Use synonyms in search or alternate links rather than two entries with indistinguishable promises.

1. Build a **destination ledger**: stable ID, existing URLs, public title, content owner, audience intent, candidate home and alternate wording. Merge proposed duplicates only when purpose, maintained content and destination are actually the same.
2. Sketch two trees against the ledger. Mark ambiguous placements and write the choice someone faces at the first fork. If those choices depend on unobserved vocabulary or grouping, use [Research methods](knowledge/research-methods.md) (`references/knowledge/research-methods.md`) to frame the evidence needed without treating a proposed tree as established behavior.
3. Trace routes from the top level, search results and direct links. For decisions, reassurance and recovery along the route, use [Wayfinding](knowledge/wayfinding.md) (`references/knowledge/wayfinding.md`) to inform the cue sequence; the card's physical sign provisions do not carry over to web navigation. If a label or route sends someone across service or channel boundaries, use [Service blueprint](knowledge/service-blueprint.md) (`references/knowledge/service-blueprint.md`) to determine whether the destinations represent the same service and what context can travel.
4. Extend the ledger into a migration map: old destination, proposed destination or deliberate retirement, alternate entry and responsible publisher. Tie each navigation label and cross-link to a destination ID so a title change isn't mistaken for a new service.

## Worked example & typical mistakes

An illustrative member portal has an “Operations” page and help requests for “moving home.” The ledger shows that updating a mailing address changes one member record, whereas transferring home service starts a separate case. “Moving home” is therefore a useful entry topic but not a synonym for either destination. From it, offer “Change mailing address” and “Transfer home service,” each with a short statement of what changes. Keep the address destination under “Personal details” with one maintained page, even when reached from search or the moving topic. Put “Operations” in the owner field, not in navigation.

Copying the address procedure into a moving section keeps both routes short at first but gives publishers two versions to update. Link instead; preserve a distinct destination only when the work and outcome differ.

## Standards, limits & handover

For public web migrations, [RFC 9110](https://www.rfc-editor.org/rfc/rfc9110.html) (2022), §§15.4.2 and 15.4.9, defines the meanings of 301 and 308 permanent redirects, including differences in possible method handling. Platform owners choose the appropriate behavior; the ledger supplies the destination, not the response code. W3C's [ARIA APG Breadcrumb Pattern](https://www.w3.org/WAI/ARIA/apg/patterns/breadcrumb/) describes breadcrumb semantics as implementation guidance, not a norm. A canonical home is a design convention here, not a promise about search indexing.

Show the tree with mapped content and routes through search and cross-links. Ask which distinctions people already make in their own words and which URLs must continue to resolve. Have publishers settle ownership and platform maintainers establish routing behavior.
