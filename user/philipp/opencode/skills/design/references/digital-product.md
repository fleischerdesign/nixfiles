# Digital Product

## When to load & job

Lead here when a decision changes how people encounter the same product across screens, roles, or visits. Make a linked product slice and an object map that show what persists, who can act on it, and what brings someone back. Use UI or interaction design for the layout or mechanics of one stop; use service design when the primary change is to the operation behind the product. The slice can simulate a service response without wiring live actions.

## Inputs & concepts

Bring existing routes, navigation and vocabulary, the component library, and examples of first and repeat use. Ask product for task priorities, engineering for stable identifiers, event meanings and persistence, and operations for who can move work forward. Use realistic records with role-specific field visibility. If authority or persistence is unsettled, label the proposed model and keep actions simulated.

A **product object** has an identity that outlasts the page that displays it. A **surface** is a projection of the object for a particular job: search helps locate it, a queue makes work actionable, and detail explains its history. **Lifecycle** is the durable state of the work; an editor loading or a request sending is surface or operation state. A **capability** is an authorized action on this object in this context, not merely the name of someone's role. A **return point** is where saved progress or new evidence becomes actionable again.

## Decisions & procedure

- **Object-first versus action-first.** Use stable detail when people revisit a record from search, activity and reminders. Lead with the next action for sequential queue work, accepting that history becomes less immediate. Draw both paths to the same object rather than giving the queue its own copy.
- **Shared semantics versus surface autonomy.** A shared lifecycle prevents contradictory accounts but costs coordination. Let teams own layout and local interaction, not a second definition of “Submitted.” Vary actions by capability: the author may withdraw while the approver can review.
- **First value versus setup; resume versus overview.** Start with a real task and defer preferences where possible. Explain a required workspace or permission up front when the task cannot start without it. On return, resume specific unfinished work when that saves effort; lead with an overview when new activity can make the old next step irrelevant.

1. Draw an **object-and-surface map** for one record. Give it an identity, display name, authoritative source, and durable milestones. Map entry routes to detail, preserving queue origin or query in navigation context rather than in the record. Write which fields and actions each viewer can see.
2. Add an **event-to-surface matrix**: for each durable change, name the actor, the evidence the interface can cite, the next actor, and what detail, list rows, and return links show. When the event depends on staff or another channel, use [Service blueprint](knowledge/service-blueprint.md) (`references/knowledge/service-blueprint.md`) to locate the handoff and ownership. For pending requests, rejection and recovery within the slice, use [Interaction states](knowledge/interaction-states.md) (`references/knowledge/interaction-states.md`) to connect outcomes to surface behavior.
3. Build the linked prototype over one shared fixture, with role and event controls for review. Enter the same record from a task queue and a return link; keep the record identity stable while allowing the entry context to differ. Reuse existing components. If a new status treatment must travel across surfaces or themes, use [Design tokens](knowledge/design-tokens.md) (`references/knowledge/design-tokens.md`) to map the shared visual role; keep business meaning in text and data, not in the token name alone.

## Worked example & typical mistakes

Suppose invoice `INV-42` appears in an approver queue and in the author's activity. Finance reports that payment is a separate process and can be unknown even after approval. In the matrix, give the record separate review and payment fields: the submission event sets review to “Submitted” and leaves payment as “No payment recorded.” The queue can label its action “Review invoice”; the author's detail can show “Withdraw” only while that capability is available. An approval reminder links to the same record. If someone else reviewed it first, the return link opens current detail with the review result instead of restoring the obsolete action.

The typical mistake is letting the submitting screen label its finished task “Complete” on the dashboard. The author reads that as the invoice being paid. Show completion of the action in the receipt (“Invoice submitted”) and keep review and payment separate wherever their distinction affects a decision.

## Standards, limits & handover

For web implementations, [WCAG 2.2](https://www.w3.org/TR/WCAG22/) §3.2.4 addresses consistent identification of components with the same functionality within a set of web pages; it does not define business status vocabulary. §4.1.3 concerns making status messages programmatically determinable without moving focus in markup-based content. A stable detail route and separate status fields are design conventions here; authorization, draft retention, and notification timing are project specifications. For token interchange, see the DTCG [Format Module 2025.10](https://www.designtokens.org/tr/2025.10/format/) on aliases and references. It is a community specification; `verify` support in the project's exporter.

Show the human the map and linked slice from first task through a role change or return visit. Identify simulated events and unresolved capabilities; a hidden button is not enforcement. Ask which work should resume, who authorizes each transition, and which event warrants a return notification.
