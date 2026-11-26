# Editorial

## When to load & job

Lead with Editorial for a book, journal, report, or long-form screen publication. Design a sequence: where readers enter, where they pause, how they get back to a passage, and how the argument relates to figures and notes. Deliver a section prototype when the manuscript or formats are provisional, and reusable styles and layouts when the scope supports implementation. Typography handles the setting of individual roles; Print handles the printer's artwork requirements.

## Inputs & concepts

Gather the manuscript hierarchy and copy status from the editor, along with actual figures, captions, credits, tables and notes. Ask production for trim, binding and constraints that affect pagination. Get screen delivery formats, reflow and citation needs from the publisher. Where content is provisional, compose a representative section and leave its eventual page count and location references open.

Distinguish a **section** (a unit of meaning) from a **spread** (two facing pages consumed together) and a **template** (a repeatable set of relationships). A **folio** identifies a print page; a **running head** gives orientation when readers land midstream. A stable section identifier names a destination even when a heading moves or a narrow screen changes the line count. Identify **dependencies** in the manuscript: a figure belongs near the passage that calls it out; a note needs both a marker and a way back.

## Decisions & procedure

- **Prose measure or modular access.** Keep a repeatable main measure for an argument read in sequence. Switch to multiple spans if readers often move among text, data and images; independent modules can make references easier to find but weaken continuity.
- **Strong opening or immediate exposition.** A full-bleed opener buys a stronger pause but can displace the first argument or separate a figure from its reference. Compare consecutive pages, not the opener alone.
- **Orientation or space.** Use running heads and folios for retrieval and citation. An opener can drop its running head when the title already identifies the section. In reflow, give readers links and anchors rather than promising stable screen page numbers.

1. Build a **sequence map**. Give each section a row with its entry, text weight, figures and first callouts, note behavior, and the anticipated exit. Use a thumbnail flatplan for print and a logical content outline for screen; connect both to the same section IDs. Mark dependencies before committing page breaks.
2. Compose an opener, a dense middle spread and the transition out. Use [Type setting](knowledge/type-setting.md) (`references/knowledge/type-setting.md`) to establish paragraph, caption and note specimens, then [Grid systems](knowledge/grid-systems.md) (`references/knowledge/grid-systems.md`) to derive spans from those roles and describe how modules stack. Translate the results into paragraph, object and page styles (or semantic markup and CSS), keeping local overrides intentional.
3. Carry one section through both media. Keep source order meaningful and map print-only elements to their screen equivalents, such as a page reference to a section link when the reference scheme allows it. Use [Print PDF](knowledge/print-pdf.md) (`references/knowledge/print-pdf.md`) when translating composed pages to the printer's specified exchange file.

## Worked example & typical mistakes

A coastal report first mentions a map at the end of one spread and explains its legend on the next. The sequence map exposes two dependencies: the first mention can tolerate a forward reference, but the interpretation cannot be separated from the map. Put the map and its legend together on the next spread, start the interpretation alongside them, and use “Figure 4” at the earlier mention. In the screen source, place the figure after the paragraph that calls it out, with the interpretation immediately after. Print retains the reveal at the turn; screen readers can reach the same figure without a spread.

A grid fit around short sample captions gives later two-paragraph captions no place to grow, making them look attached to the wrong image. Let caption depth vary inside a shared figure module; trade some image area on the busiest spread rather than breaking the association.

## Standards, limits & handover

[EPUB 3.3](https://www.w3.org/TR/epub-33/), W3C Recommendation, “Package document” and “EPUB navigation document,” defines the spine and navigation for an EPUB edition. Running heads and opener treatments are editorial conventions. The publisher's brief decides whether to expose print page locations in the digital edition. Adobe InDesign Help's [Parent pages](https://helpx.adobe.com/indesign/using/parent-pages.html) describes repeatable page elements; `verify` the installed version.

Show consecutive spreads and the equivalent narrow sequence using real copy. Hand over the sequence map, styles and note and reference rules. Ask whether readers primarily read through or return to cite sections, and whether editions need shared reference locations. The editor owns the manuscript and any copy cuts; the publisher or production team supplies format and binding decisions.
