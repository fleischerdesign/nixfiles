# Accessibility

## Use when

Translate a web task or piece of content into an implementation annotation sheet: semantic elements, names and states, keyboard and focus behavior, and output that carries the same task-relevant information when the visual or audio presentation is unavailable.

## Inputs

Bring the flow with real labels, content and chart meanings, control types, update events, and the required web delivery context. Get the applicable standard and scope from the project owner; a target written into the brief is a project specification. If copy or components are provisional, annotate the intended purpose and behavior rather than treating placeholder text or a mockup as the implemented equivalent.

## Procedure

1. Map each element by purpose before styling. Use a native button for an in-place action, a link for navigation, a labeled field for input, and headings and lists for structure. For controls, record the exposed role, name, and current state or value. Reach for a custom widget only when native elements cannot express the interaction; adding an ARIA role does not supply keyboard behavior.
2. Derive the name from visible language when possible. Associate the visible label with the field or control so people using different inputs share the same vocabulary. Name an icon-only control by its action and, if needed, its object; don't describe its glyph. Put supplemental instructions or related errors in a programmatically associated description where appropriate, rather than expanding the name into a paragraph. Keep decorative imagery out of the equivalent output.
3. Annotate the keyboard path in task order: entry, actions, interruption, recovery, and return. Give the focused element a visible indicator and account for authored overlays that can cover it. Keep focus stable across routine updates; when a control disappears, name a logical successor. Expose a background update as a status message when it needs to be conveyed without moving focus.
4. Write an equivalent for the actual decision, not a transcription of decoration. For a chart, give the main relationship in text and provide underlying values, gaps, and units when readers need exact lookups. If filters change the visual output, keep the equivalent tied to the same selection. If a sound is the only sign that a task completed, give completion a non-audio representation at the same point in the flow.

## Limits

WCAG criteria apply within their own scopes; the techniques above are design and implementation methods, not a blanket statement about the artifact. APG gives usage guidance, not normative requirements. Platform and assistive-technology behavior and people's experience of the real task are not established by annotations alone.

## Worked example

An illustrative service dashboard uses a funnel icon to apply filters to a chart. Give the button the visible name “Apply filters” and treat the icon as decorative. On activation, retain focus on the button while the results region updates, then expose “Showing results for North” as a status message. Head both the visual trend and its textual summary with the active region. Put a labeled values table below them and write “Not reported” in the missing period's cell instead of letting the absence become a zero or a silent blank.

## Sources

- W3C [WCAG 2.2](https://www.w3.org/TR/WCAG22/), Recommendation of 12 December 2024: §§1.1 (text alternatives), 2.1 (keyboard accessibility), 2.4 (navigation and focus), 4.1 (name, role, value and status messages). See also SC 2.5.3 for visible text in control names.
- W3C ARIA APG, [Providing Accessible Names and Descriptions](https://www.w3.org/WAI/ARIA/apg/practices/names-and-descriptions/): implementation guidance on choosing names and descriptions and preferring visible text where possible.
