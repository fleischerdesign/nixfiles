# Scene studies

## Use when

Build a lightweight 3D study to reason about form, viewpoint, or layer relationships before producing assets. Deliver a proxy scene, a named set of views, and a layer map that makes overlap, contact and dependencies visible.

## Inputs

Bring reference views, known dimensions and units, likely eye positions or camera movement, and any plate or anchoring geometry. Ask the production or runtime owner for coordinate conventions, required asset format, and target framing. Record which geometry is supplied, assumed, or illustrative. Without measured dimensions, use relative scale and a labeled reference object; leave fit and reach unresolved.

## Procedure

1. Write the spatial question beside the scene. To study an opening or an occlusion, spend geometry on the profiles and volumes that create it. For surface finish, use simple silhouette geometry and a separate material comparison. Use planes, boxes, or cutouts as proxies where their limits do not change the answer. A flat texture will not show a volume crossing a silhouette or casting its own shadow.
2. Choose projections by the comparison. Use aligned orthographic views for relative proportions; add a section when hidden depth or a movement envelope is the subject. Choose a perspective view for what a viewer actually sees. Record camera position, aim, projection, and framing or lens settings so variants can share a camera. When comparing an overlap through movement, mark the start, crossing, and end views; a single favorable frame hides the problem.
3. Keep a layer map distinct from camera views. List plate or backdrop, setting, subject, foreground occluders, light and shadow effects, and annotations as relevant. For each, say what belongs in front, what must hold out another layer, and which elements need shared contact shadows or reflections. In a 3D scene, depth can change the order with the camera; don't treat the list as a universal stacking order. Blender collections and view layers can expose isolations without duplicating or nudging the geometry.
4. For interchange, record units, axis orientation, and the reference origin in the source and target. Explain where an export conversion happens. A known-scale reference and named axis marker make orientation visible in the receiving view; they do not replace actual measurements.

## Limits

Proxy views communicate relationships, not physical clearance, lighting performance, headset comfort, or the accuracy of a camera solve. Tool and format conventions do not establish a project's units at source or how a particular importer handles conversion; `verify` the versions in use.

## Worked example

In an illustrative lobby study, a freestanding marker must remain visible as someone approaches from the side. Model the marker as a slab, the masking column as a box, and the viewer as a named camera at an assumed eye position. In plan, mark the approach positions and draw a line from each position to the marker's label. The perspective crossing view shows the column covering the label even though the frontal view shows it cleanly. Keep the column in the setting and identify it in the layer map as the occluder; isolate it only in a diagnostic view. Present the shifted marker and the original from identical cameras so the human can judge the change.

## Sources

- Blender 4.5 LTS Manual, [Cameras](https://docs.blender.org/manual/en/4.5/render/cameras.html) and [View Layers](https://docs.blender.org/manual/en/4.5/render/layers/introduction.html): official documentation for projection and scene-layer controls.
- Khronos [glTF 2.0 specification](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html), §3.4, “Coordinate System and Units”: right-handed, Y-up coordinates and meters for linear distances within glTF, not a rule for authoring tools.
