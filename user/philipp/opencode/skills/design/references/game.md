# Game Design

## When to load & job

Lead here when the artifact is a playable prototype and the question is how rules feel in play. Build a loop with a repeated decision, recognizable consequences, and a chance to learn from them. Use interaction design for an isolated control and immersive design for spatial input or presence. Neither substitutes for deciding what the player is trying to accomplish under the game's rules. Leave campaign-scale content, final assets and production infrastructure outside the slice.

## Inputs & concepts

Bring the intended player experience, platform and controls, existing rules, and reference moments rather than just game titles. Ask the project owner who will play and what familiarity and session length to expect; label assumptions when these are missing. Ask what must survive between attempts. That determines whether an early loss is a short lesson or a large setback.

In the **MDA** model, mechanics are rules or procedures, dynamics are behaviors that emerge in play, and aesthetics are the experiences players have. Translate “tense” into an observable choice with an opportunity cost, not a mood board. A **core loop** links perception, choice, resolution and changed conditions for the next choice. A **feedback loop** within it amplifies or counters a change over successive turns. A sound or flash is feedback to the player, but is not by itself a feedback loop in the rules.

## Decisions & procedure

- **Improvisation versus execution.** Let a move solve one problem while creating another for improvisation: spending lantern light reveals a shortcut but leaves less for the return. Use a reliable rule with room for mastery when precision is the pleasure, accepting less surprise.
- **Compounding gains versus sustained tension.** Let resources amplify a lead when the fantasy is growing powerful. When decisions should stay difficult, make treasure change movement or attract danger. Show why the added cost follows from the gain so success does not feel arbitrarily penalized.
- **Practice versus commitment.** Make early retries short so the player can relate a new choice to its outcome. Costlier losses can make later decisions feel weighty, but they also reduce time spent practicing the mechanic.

1. Draft a **turn ledger** for the repeated decision. Write what the player can see before choosing, the legal actions, the order of rule resolution, the resource change, and what carries forward. Include one actual sequence of turns with example values, and make unclear ordering visible before implementing it. Use [Feedback loops](knowledge/feedback-loops.md) (`references/knowledge/feedback-loops.md`) if a gain or cost changes subsequent opportunities and you need to explain the return path.
2. Implement the resolution rules separately from input, drawing and playback. Emit named events for consequences like a patrol advance or charge spent, so presentation can distinguish preview from commitment. Use [Motion timing](knowledge/motion-timing.md) (`references/knowledge/motion-timing.md`) to make anticipation, impact, and the return of control legible. Use [Sound cues](knowledge/sound-cues.md) (`references/knowledge/sound-cues.md`) to attach tells and results to those events without making essential information sound-only.
3. Build an early encounter that exposes the consequence and a later encounter that combines the same rule with a competing goal. Keep geometry and assets simple enough to compare versions. Add a quick restart with a recorded starting arrangement so a human can replay the same situation with another choice. Expose the few values that change the intended experience.

## Worked example & typical mistakes

In an illustrative turn-based lantern game, the later room offers a shortcut past a patrol. The ledger says that revealing the shortcut spends one charge but does not move the player. The patrol then advances before the next decision. That order is easy to miss: if the same command also moves the player, “reveal” becomes a gamble on landing somewhere unseen. Preview the patrol's next tile with a visible marker, let the reveal expose the route and reduce the charge count, then resolve the marked patrol move before accepting movement. In the early room, expose the same ordering with no patrol in reach. The later room now asks whether the route is worth a turn and a charge, not whether the player can infer hidden resolution rules. The charge cost is an example value.

Adding health to a puzzle enemy can stretch a solved encounter into repeated turns. To increase planning pressure, change when the enemy moves or which tiles it blocks, and give that change a readable tell.

## Standards, limits & handover

Hunicke, LeBlanc, and Zubek's [“MDA: A Formal Approach to Game Design and Game Research”](https://users.cs.northwestern.edu/~hunicke/MDA.pdf) (2004), “MDA in Detail,” is a design model, not a normative standard. For a Godot 4.5 prototype, the official [InputEvent guide, “Input actions”](https://docs.godotengine.org/en/4.5/tutorials/inputs/inputevent.html#input-actions), describes named actions that can stand apart from their device bindings. `verify` the engine version and target platform's input requirements; default bindings, timing, and loss costs are project choices.

Share the playable loop, controls, restart, early and later encounters, and the adjustable rule sheet. Ask which strategies should pay off and whether a lost attempt should invite experimentation or make choices feel weighty. A short slice lets the human judge that decision in context; it does not establish campaign balance.
