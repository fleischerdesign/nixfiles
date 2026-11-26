# Sound cues

## Use when

Place sound against a picture cut or interaction so a listener knows what happened, where to attend, or what to anticipate. Produce a cue sheet that can be read with a temp track, an animatic, or an interaction recording.

## Inputs

Bring a versioned cut or event trace, dialogue and music references, the intended playback contexts, and any mute or repeat-use constraints. For picture, get the timebase and actual picture events from editorial; for interaction, get the event that authoritatively indicates completion. Get delivery levels, measurement methods, and peak limits from the destination's specification. If the cut is provisional, spot against named beats and mark timecodes as unset.

## Procedure

1. Identify the instant or span the cue serves: an impact, a reveal, recognition of a voice, or a confirmed action. Give it an ID and anchor it to a frame or event. Write whether its onset leads, coincides with, or follows that anchor. A lead-in can prepare an audience; don't use one to imply a service succeeded before the outcome is known.
2. Draft the cue sheet with anchor, in and out, intent, foreground or background placement, competing layers, and any interruption or repeat rule. Foreground is relative to neighbors: name which line or effect should lead, and which bed continues or recedes underneath. Mark intentional silence and distinguish it from keeping room tone while music drops. If animation or editing changes, the named anchor tells the editor what to re-spot.
3. Describe how the same cue should work in the real listening context. Headphones can carry fine texture; a phone in a noisy space may need a more distinct attack or a less crowded register. Ask for that contrast before specifying more level. Give essential information a visible equivalent at the same event if muted playback matters. For repeated actions, decide when cues retrigger, collapse into a single cue, or stay silent.
4. Keep listening notes separate from delivery values. A direction like “keep the spoken name in front of the bed” is a relationship for the mix; it is not a loudness or true-peak target. Attach the destination's actual spec when available.

## Limits

A cue sheet communicates timing and intent, not intelligibility on a particular device or final mix behavior. Listen in the stated contexts with the audio team. Measurement methods and broadcast recommendations are not default specifications for apps, games, or other destinations.

## Worked example

An illustrative export flow has three anchors. At `export_requested`, show “Exporting…” and mark sound as intentionally absent; sounding a chime would suggest the file is ready. At `file_ready`, put the completion cue on the event, with a short distinct attack in front of the existing bed but behind any active spoken instruction. Pair it with “Export ready” beside the download control. At `export_failed`, show the recovery action and omit the success motif. The sound designer can spot the cue on the event in a temp mix without guessing where the spinner ends.

## Sources

- Michel Chion, [*Audio-Vision: Sound on Screen*](https://cup.columbia.edu/book/audio-vision-sound-on-screen/9780231185899), 2019 edition, chapter 3, “Lines and Points,” on audiovisual relationships; interpretive method, not a timing norm.
- [ITU-R BS.1770-5](https://www.itu.int/rec/R-REC-BS.1770/en) (11/2023), programme loudness and true-peak measurement algorithms. [EBU R 128](https://tech.ebu.ch/publications/r128), loudness normalisation for broadcast delivery; `verify` the revision and destination adoption before quoting delivery values.
