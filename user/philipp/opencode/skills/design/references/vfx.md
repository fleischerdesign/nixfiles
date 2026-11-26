# VFX

## When to load & job

Use this for an effects shot's previz, look development, or compositing plan. Decide what belongs in the photographed scene, what must be added or removed, and what makes the layers feel like one shot. Let film and video lead if the edit determines whether the effect is seen at all; let 3D lead if the object must be designed before it can be put into a plate. A moving proxy or shot brief is not a final composite.

## Inputs & concepts

Bring the cut, shot IDs, source plates, and available lens and camera notes. Ask editorial and post for frame ranges, handles (source material beyond the cut), retimes, and the correspondence between plate and cut frames. Get the approved color configuration and any witness views, clean plates, or lens references from production. If the plate or metadata is missing, use a marked proxy to show placement, depth, and timing; leave tracking and color matching unresolved.

A **plate** is the photographed image feeding the composite. A **planar track** describes how a surface moves in the image; **parallax** is the relative apparent movement of objects at different depths as viewpoint changes. A track says where an element moves; a **matte** says where it appears. A **holdout** uses the foreground's coverage to hide layers behind it. Keep these dependencies separate: a tracked window boundary does not tell you where a person blocks the window.

## Decisions & procedure

- **Follow a plane or solve the camera.** Use a planar track for a graphic fixed to a wall. When viewpoint changes reveal depth, plan a camera solve with elements at separate depths. The extra setup preserves relative movement that a single plane flattens.
- **Use the plate or replace it.** Keep photographed foreground where it provides contact, occlusion, and light. Replace more when seams cross moving detail or the plate cannot carry the look; anticipate rebuilding those interactions.
- **Integrate or deliberately separate.** Plan spill, shadows, and edge behavior for an effect that belongs in the room. A deliberately graphic effect can forgo some of that integration, but then reads as a separate layer.

1. Mark the visible result and its onset in the cut. Identify the frames where a seam, overlap, or changing viewpoint can expose the construction. For timing an effect against the shot's action, use [Motion timing](knowledge/motion-timing.md) (`references/knowledge/motion-timing.md`).
2. Make a **shot dependency diagram**: plate, replacement area, tracks and transforms, independently moving holdouts, and additions such as shadows and reflections. Connect each layer to the element that drives its motion. Use [Scene studies](knowledge/scene-studies.md) (`references/knowledge/scene-studies.md`) when proxy depth and camera views are needed to explain a crossing or parallax.
3. Stage a moving composite with placeholders for unresolved elements. Identify where lens distortion is handled and keep added elements and mattes in the same image coordinates at the merge. For the plate, CG, and review color route, use [Color management](knowledge/color-management.md) (`references/knowledge/color-management.md`). Put the proxy shot back in the cut so the human can see what draws attention.

## Worked example & typical mistakes

For a window replacement, constrain the new view to the tracked opening, then use a separately moving actor matte to suppress that replacement where the actor passes in front. Keep hair edges as a separate problem from the solid body: a soft holdout over the original plate can still leave the old exterior visible in semi-transparent edges. Mark that region for edge reconstruction or a clean-plate-assisted treatment rather than making the matte harder. If the outside view needs parallax, give it its own depth model; the window track still locates the aperture. A clean start frame hides the hair problem, so show the crossing in motion.

## Standards, limits & handover

For alpha compositing conventions, Porter and Duff, [“Compositing Digital Images”](https://doi.org/10.1145/800031.808606), SIGGRAPH 1984, describes premultiplied representation and the `over` operator. Image interchange alone does not identify the production color route; see the OpenColorIO [Displays & Views documentation](https://opencolorio.readthedocs.io/en/latest/guides/authoring/displays_views.html) for working-to-view configuration behavior, and `verify` the deployed version. The production specification supplies the frame mapping, lens workflow, and color configuration.

Show the beat in the cut, annotated start and overlap frames, and the diagram with tracks, mattes, and plate dependencies. Ask whether the effect should be noticed or accepted as part of the photographed scene. The compositor's next artifact is a moving study with the actual plate and agreed color pipeline.
