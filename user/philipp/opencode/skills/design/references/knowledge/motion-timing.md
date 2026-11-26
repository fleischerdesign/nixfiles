# Motion timing

## Use when

Turn a state change or visual sequence into a timing strip. Give each beat a purpose, show when the result is readable or usable, and specify what happens if the sequence is interrupted or played with reduced motion.

## Inputs

Bring start and end states, story or task beats, interruption events, and the project's motion tokens or edit timeline. Identify which controls or words must be usable and when. For time-based media get the frame rate and any fixed picture or sound cue from production. Without specs, show relative beats with provisional durations rather than assuming production values.

## Procedure

1. Write what the viewer needs to notice, track, or read. Mark trigger, first visible response, meaningful arrival, readable hold, and exit on the strip. Line up concurrent tracks for object motion, copy, control availability, and relevant sound. Put a beat on the strip only if it changes what the person knows or can do.
2. Allocate the hold before decorating the movement. A title's reading hold starts when the whole line can be read, not when the first letter appears. Where the task demands an immediate response, acknowledge input promptly and avoid tying readiness to the end of a decorative transition. Use stagger only when order carries meaning; if several items must be compared, exposing them together may be clearer.
3. Specify easing per moving property as a mapping from elapsed progress to motion progress. For example, ease out to arrive quickly and settle; use linear progress when position should track elapsed time at a constant rate between fixed endpoints. Record the project token or chosen curve, rather than relying on “smooth” as an instruction. When input reverses or retargets a move, start from its current visual value; replace pending choreography rather than stacking it. Keep the destination and usable state explicit so an old animation's completion cannot restore stale state.
4. Write a reduced-motion strip for the same trigger and outcome. Replace substantial travel, zoom, or parallax with a cut or a stable local cue, such as the same selection label in both states. Keep reading time where it serves the content, and keep task feedback, control availability, and focus meaningful. On the web, use the reported reduced-motion preference to select the alternative.

## Limits

Easing and hold choices are design conventions, not fixed duration norms. The media query reports a preference; it doesn't decide which cues convey equivalent information. Exact frame boundaries and interactive timing come from the project's delivery or implementation constraints.

## Worked example

An illustrative card expands into a detail pane. The timing strip marks “Open requested” and immediate selection, then the shared thumbnail travels to the pane while its heading appears in place. If Close arrives mid-flight, the pane heads back from its current position and the editor does not briefly become active. In reduced motion the pane appears without travel, repeats the thumbnail and item name, and offers the same controls. The content stays until dismissal in either version; its hold isn't a decorative delay.

## Sources

- Frank Thomas and Ollie Johnston, *Disney Animation: The Illusion of Life* (1981), principle of timing; animation craft, not interface duration guidance. Page and section locator: `verify`.
- W3C [CSS Easing Functions Level 1](https://www.w3.org/TR/css-easing-1/), Candidate Recommendation Draft, §2, easing functions; [Media Queries Level 5](https://www.w3.org/TR/mediaqueries-5/), Working Draft, §12.1, `prefers-reduced-motion`. These define web mechanisms, not choreography.
