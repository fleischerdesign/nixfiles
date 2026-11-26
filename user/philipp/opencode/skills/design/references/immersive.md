# Immersive Design

## When to load & job

Lead here for an AR, VR, or mixed reality prototype where position, scale, movement, or physical surroundings change the task. Build a runnable headset slice or a labeled desktop simulation showing what people notice, reach, and do as tracking and context change. Use 3D design for the appearance and geometry of an asset, or game design when the main question is what the rules reward. Neither a headset slice nor a simulation is a deployment pipeline.

## Inputs & concepts

Bring the target device, runtime and inputs, tracking and anchor support, intended room, posture, and expected session length. Ask the deployment team for geometry, fixed obstacles, usable area and supported input modes. Without hardware or site access, label the assumed geometry, hand poses and viewpoints; leave reach, visibility and comfort for on-device review.

A **reference space** specifies what a pose is relative to: a viewpoint, local origin, or other supported frame. **Registration** is alignment between virtual content and its physical referent. An **anchor** is a reference used to maintain that relationship, not proof that it is still accurate. Keep the remembered identity of an anchor separate from whether its pose is currently usable. **Direct manipulation** uses proximity and depth for selection or placement; a **ray** projects a selection direction and needs a visible target before commitment.

## Decisions & procedure

- **Registered cues versus summonable controls.** Anchor a cue when its location carries meaning, such as a label identifying a part. Put portable controls in a summonable panel when people need to recover them away from the surface; it is less spatially specific and may cover the work.
- **Stationary interaction or teleportation versus continuous travel.** Favor stationary work or teleportation when orientation matters more than experiencing the route. Teleportation reduces simulated travel but interrupts continuity. If continuous movement is central, let people start and stop it and show an alternative from the same first-person viewpoint.
- **Direct reach versus distance interaction.** Use direct reach when hand position and depth help with placement. Offer ray selection or a discrete action for tasks where range, posture or tracking makes reach difficult. Distance input saves effort but may offer less fine control, so preview the target and effect.

1. Create a **spatial storyboard**: a plan and first-person views for approach, selection, commitment and return. Annotate the coordinate frame of each cue, the physical reference if any, and what should be visible at the moment of decision. Use [Scene studies](knowledge/scene-studies.md) (`references/knowledge/scene-studies.md`) to build proxy geometry and compare occlusion across viewpoints.
2. Assign interaction and placement authority separately. A local preview can follow a pointing direction without gaining authority to fix content to a surface. Map runtime signals to behaviors for normal tracking, uncertain placement, and recovery. Use [Interaction states](knowledge/interaction-states.md) (`references/knowledge/interaction-states.md`) to decide what remains visible, actionable, and retained when tracking changes during a task.
3. Implement one first-person task, with a way to simulate tracking loss or unavailable spatial mode. Expose a flat path for work that does not depend on placement. Use [Motion timing](knowledge/motion-timing.md) (`references/knowledge/motion-timing.md`) to express transitions without tying availability to animation, and to provide equivalent local cues where movement is not needed. Record walkthroughs from the user's viewpoint, not just a spectator camera.

## Worked example & typical mistakes

In an illustrative tabletop assembly guide, the storyboard ties a reticle to the current pointing direction and a part label to an established tabletop anchor. Tracking drops just before the person accepts a placement. Retain the selected part and step, suspend placement, and replace the reticle with a non-spatial prompt explaining how to restore tracking. If the original anchor resolves, redisplay the preview there and ask for placement again; do not silently commit the previous gesture. If only a new surface is available, offer explicit re-placement. The parts list and instructions can still be read in a flat view, but that view cannot identify a physical hole.

The common mistake is keeping the old placement pose in view as if it were current. After drift or relocalization the label can appear attached to a different surface. Treat the saved pose as remembered data, not a present-tense cue the person should act on.

## Standards, limits & handover

The Khronos [OpenXR 1.1 specification, “Spaces”](https://registry.khronos.org/OpenXR/specs/1.1/html/xrspec.html#spaces), distinguishes pose validity from tracking in space location flags. A runtime can still report a valid component that is not currently tracked; use the distinction rather than assuming a returned pose means live registration. `verify` the target runtime and its anchor extensions. Frame semantics are part of the API specification; room geometry and allowed posture come from the project. Teleportation and summonable panels are design conventions, not comfort guarantees.

Hand over the runnable slice or labeled simulation, spatial storyboard, first-person walkthrough, tracking-loss path and non-spatial path. Ask which cues must remain physically registered and whether seated, standing, or both postures must work. Have the deployment team review apparent scale, reach, occlusion and movement on target hardware in the intended space.
