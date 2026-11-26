# Physical Product (Industrial)

## When to load & job

Use this to brief a handheld tool, appliance, or other manufactured object. Show how a person operates, cleans, and services it, and which parts of the form are consequences of those tasks. Deliver an annotated use sequence and two physically distinct concepts, not manufacturing drawings. Packaging leads if the decision concerns sale presentation or the pack rather than operation of the object itself.

## Inputs & concepts

Get the operating sequence from users or the owner, including setup, failed attempts, cleaning, and the least convenient service action. Record whether the object sits on a bench, hangs from a bracket, or travels with the user; whether hands are gloved or occupied; and where removed parts can be put down. Get mating geometry and mounting positions from measured samples or the owner's drawings. Request volume ranges, assembly assumptions, and candidate process limits from the manufacturing partner. Without those inputs, use relative geometry and mark fit, material, and process as open.

The **interface** is where another part, a person, or a mounting surface constrains the design. A **datum** is the reference from which that relationship is drawn, such as the wall mounting face rather than the outer shell. A **load path** names where the user's effort goes: a release pressed from the front may put its reaction into the bracket, whereas a pull can make the product shift if nothing holds it. That observation tells you where a drawing needs a restraint or a second hand; it does not size the bracket. Separate a consumable routinely handled by an operator from a component opened only during workshop repair.

## Decisions & procedure

- **Compactness versus a braced gesture.** A smaller body may suit storage but force a second hand to stabilize it. Favor a positive support surface when the user cannot put down what they are holding; show who or what takes the reaction.
- **Wipe-down versus repair access.** An uninterrupted skin is simpler to wipe, but may bury a wear part behind unrelated assemblies. Put seams where opening makes sense and compare their exposure to dirt in the installed orientation.
- **Tooling commitment versus unit effort.** Low-tooling construction can suit uncertain demand at the cost of more assembly per unit. A tooled enclosure can change the recurring work but commits the team to geometry earlier. Compare supplier hypotheses at the same volume scenario.

1. Draw the hardest task in the installed context before drawing the shell. Start at the last normal operating state and finish at the first usable state after service. Include the user's other hand and whatever it is holding.
2. Make a **task–interface ledger**: for each action, name the moving part, the fixed reference, what supplies restraint, and where the removed part ends up. For spatial interference during operation or removal, use [Fit envelopes](knowledge/fit-envelopes.md) (`references/knowledge/fit-envelopes.md`) to show the relevant gesture and extraction space.
3. Turn the ledger into two construction concepts. On each sketch mark the enclosure split, access direction, and which modules remain attached during replacement. Ask suppliers how they would form, fasten, and assemble that split; do not assign material properties or tolerances from appearance.
4. If the split changes service life or replacement, use [Lifecycle scope](knowledge/lifecycle-scope.md) (`references/knowledge/lifecycle-scope.md`) to frame equivalent service and request evidence before making an environmental comparison. Show the intended service sequence alongside the concepts so the reader sees what actually gets replaced.

## Worked example & typical mistakes

A dispenser is mounted against a wall and the attendant normally holds a fresh cartridge when opening it. In the ledger, “unlatch” and “withdraw empty” are different actions. A front release can be reached easily, yet pulling the spent cartridge forward can pull the whole dispenser off an unrestrained bracket. One concept leaves the body attached and opens the refill bay sideways; its extraction path depends on which side has an adjacent unit. Another brings the cartridge out at the front and asks the manufacturer how the bracket can retain the housing during the pull. The two sketches show the empty cartridge's destination as well: a temporary tray could free the hand needed to insert the fresh one. Neither sketch promises one-handed service.

Putting the refill door on the rear for an uncluttered face makes an installed unit move for every refill. Draw from the mounting face with the unit in place; compare front and side access before polishing the exterior.

## Standards, limits & handover

[ISO 7250-1:2017](https://www.iso.org/standard/65246.html) defines basic body measurements and landmarks, not product clearance values; `verify` applicable edition and measurement section. [ISO 14040:2006](https://www.iso.org/standard/37456.html) supplies the life-cycle assessment framework, not evidence for a product claim; `verify` applicable amendments. Supplier process limits are project specifications. Ledger labels and dashed provisional edges are drawing conventions; the dispenser configuration above is illustrative.

Show the annotated sequence, matched concept views, and open process and material decisions. Ask who changes the refill and what may move during service. An industrial designer provides a handling mock-up with representative users; the manufacturing partner provides process evidence and samples. Final dimensions, material selection, fabrication, and product safety determinations remain outside the study.
