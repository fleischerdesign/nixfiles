# Inclusive Design

## When to load & job

Use this alongside the lead deliverable when a design assumes people can perceive, understand, act, or recover in only one way. The lead module controls the medium; this module traces exclusion across the whole task, including handoffs between media or teams. Deliver annotated task variants, requirements by owner, and a plan for people to try the task in context. Do not present the brief as evidence of equitable access or the experience of actual participants.

## Inputs & concepts

Bring the task and its consequences, observed use contexts, any first-person accounts, actual channel capabilities, and the project’s stated standards. Ask operators which steps can be completed without staff, when staff are available, and where people are required to disclose information. Ask participants how they want to take part rather than inferring accommodations from a diagnosis or category.

An **exclusion mismatch** is a dependency the design imposes under particular conditions, not a trait that explains a person. A person with one hand, an injured wrist, or a bag in hand may all encounter a two-handed control; these permanent, temporary, and situational constraints prompt different questions, not interchangeable accounts. Label imagined cases as hypotheses. **Equivalent access** here means preserving the task outcome and its practical conditions, including timing, privacy, and recovery. A second route may reach the same nominal endpoint while making a person wait longer or reveal why they need it.

## Decisions & procedure

- **Flexible shared path or parallel route.** Prefer removing the dependency on the shared path when this serves the task without extra setup. A distinct route can address a barrier the main medium cannot remove, but it adds maintenance and may become second-class if updates or support do not reach it.
- **More ways to start or continuity through recovery.** A new entry route is valuable when discovery is the barrier. When someone can start but cannot correct an error or resume after a handoff, spending effort on another entry leaves the task unfinished.
- **Asynchronous or supported live participation.** An asynchronous walkthrough lets people set the pace but makes clarification slower. A supported session can reveal workarounds, yet requires scheduling and may change how people act. Budget for the accommodations people request.

1. Draw a **task continuity strip** across channels: discovery, action, confirmation, interruption, and recovery. Put the task-critical information or authority at the point where it is needed. Use [Inclusive constraints](knowledge/inclusive-constraints.md) (`references/knowledge/inclusive-constraints.md`) to translate a mismatch in the strip into a requirement and compare equivalent paths.
2. Annotate handoffs with the information or state that must survive, the owner responsible for it, and the consequence if the receiving channel is late or unavailable. Favor changes to the shared source when two outputs need the same instruction. Where an alternate route relies on staff, show what participants can do without staff and what cannot yet be completed independently.
3. Assign annotations to the relevant deliverables: interface, messages, signage, or support instructions. For web implementation, use [Accessibility](knowledge/accessibility.md) (`references/knowledge/accessibility.md`) to specify semantics, names, focus, and equivalent output for the affected interaction. Do not transplant web requirements to a physical setting.
4. Prepare a grounded episode for participants and operators to discuss, including a disruption. Offer participation modes, budget for requested support, and let people describe a barrier without having to reenact it.

## Worked example & typical mistakes

A station announces a late platform change. The strip shows that the critical event is not hearing the announcement; it is knowing where to go while approaching the platform choice, and recovering if already on the old platform. Specify that the operational update carries both destination and replacement platform into the concourse departure display and the old platform’s display, alongside the spoken cue. Identify who publishes the update and who owns recovery if a display is unavailable. A help point may be useful, but reaching one should not be the only way to learn whether to turn back.

Publishing a transcript elsewhere relocates the instruction away from the decision. It may preserve the words but not the opportunity to act on them; carry the instruction to the decision point and show the recovery route.

## Standards, limits & handover

NC State’s Center for Universal Design, *The Principles of Universal Design*, v2.0 (1997), principles 1, 2, and 4, gives design guidance on equitable use, flexibility, and perceptible information. For web content, W3C [WCAG 2.2](https://www.w3.org/TR/WCAG22/) (Recommendation, 12 December 2024), e.g. SC 2.1.1 (Keyboard) and 4.1.3 (Status Messages), supplies normative criteria within their scope. The task strip is a working convention; channel capabilities and jurisdictional targets are project inputs. `verify` the applicable built-environment or transport standards separately.

Show the human the task variants, annotated handoffs, owners, and unresolved barriers. Participants need to try the implemented task in context; a specialist interprets applicable standards. Where must people finish without asking for help? Which team can keep each route current?
