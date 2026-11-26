# Immersive Design

## When to load & job

Load this for an AR, VR, or mixed reality prototype where position, scale, movement, or the physical surroundings change the interaction. Design what people notice, reach, and do as tracking or context changes. A headset slice or desktop simulation is not a production pipeline.

## Inputs

Bring the target device and inputs, tracking and anchor support, intended space, posture, and expected session length. Get room and device constraints from the deployment team. Without hardware or site access, show a simulation with assumed geometry, and leave reach, visibility, and comfort for device-side review.

## Decisions & process

Anchor information to a real surface when its location carries meaning, such as an assembly cue beside the part. Spatial relevance depends on reliable registration. For controls that need to travel with the person, consider a summonable panel instead; it's easier to recover but less tied to place and may obscure the scene.

In VR, prefer stationary interaction or teleportation when orientation matters more than continuous traversal. Teleportation limits forced camera motion but breaks the sense of traveling a route. If continuous movement is central to the experience, expose a movement alternative and let people control when movement starts and stops. Show both from the user's viewpoint.

Use direct reach for nearby manipulation when the action benefits from depth and hand position. Offer ray selection or a discrete control when distance, posture, or tracking makes reach awkward. Distance interaction reduces effort but can make fine placement less expressive; make the target and resulting action apparent before commitment.

## Typical mistakes & examples

When an AR tabletop object follows the last estimated pose after tracking drops, it can appear attached to the wrong surface. Suspend placement, tell the person how to restore tracking, and resume from a known anchor or offer explicit re-placement. If spatial mode is unavailable, offer a flat view of the task where placement isn't essential.

## Deliverables & questions for the human

Show a runnable slice or labeled simulation, a first-person walkthrough, and the tracking-loss and non-spatial paths. Ask which cues must stay physically registered and whether the task must work seated, standing, or both. Have someone with the target hardware review the assumed space and interaction.
