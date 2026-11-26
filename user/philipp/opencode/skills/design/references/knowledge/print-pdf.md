# Derive a print PDF from the printer’s brief

## Use when

The layout must become a PDF for a printer or fabricator. Produce an annotated geometry sheet and an export recipe so the finished edge, artwork beyond it, and responsibility for color conversion are explicit.

## Inputs

Get finished dimensions and orientation, page sequence, binding or folds, bleed per edge, safe insets, and any finishing guides from the printer’s job specification. Record units and distinguish a flat size from a folded size. Ask whether the printer wants single pages or spreads, who imposes them, which marks belong in the file, and which PDF variant, printing condition, profile and conversion policy they use. With no brief, draw a trim-size study with provisional dimensions rather than adopting a preset as a production specification.

## Procedure

1. **Draw from the cut inward and outward.** Set the document page to finished trim, not trim plus bleed. Extend edge-to-edge images and solids past each cut by the supplied bleed. Draw safe insets inward from trim and add separate fold and binding allowances where supplied. Move critical faces, type and lines inside those guides; extend background pixels rather than scaling the whole layout.
2. **Map the guides to PDF geometry.** The TrimBox describes the finished rectangular page; the BleedBox bounds the area available for bleed. The MediaBox bounds the whole PDF page, including any space needed for requested marks. The CropBox can affect what a viewer displays; it does not communicate safe area. Safe insets, crease lines and irregular cuts belong on the working diagram or in the agreed finishing layer, not in a new PDF page box.
3. **Choose the exchange and color settings separately.** Use PDF/X-4 when requested for complete exchange, including workflows that retain transparency and color-managed assets. State whether linked images stay tagged for downstream conversion or are converted on export. Name the intended printing condition in the output intent; setting it does not itself convert object colors. Record any printer instructions for process values, spot plates and overprint. PDF/X-4p refers to an external ICC profile and is not a substitute for PDF/X-4.
4. **Document the handoff.** Record pages versus spreads, box geometry, marks, color policy, spot names, and any printer-supplied image compression or resolution settings. Give the human a trim-view layout and the annotated geometry; tell the printer which areas the physical proof should make visible.

## Limits

PDF/X governs data exchange, not a job’s bleed, legibility, stock or finishing tolerances. InDesign preset names describe app behavior, not printer policy. A rectangular box does not encode a shaped cut, and a PDF preview does not show the variation of a finished run.

## Worked example

Illustrative printer values for a postcard: trim 150 × 100 mm, bleed 3 mm on each edge, safe inset 5 mm, no printer’s marks. Build a 150 × 100 mm page and export a 156 × 106 mm bleed extent. The return address stays at least 5 mm inside trim, not 5 mm inside the outer PDF edge. Extend the sky beyond the cut while leaving the portrait in place. If the printer explicitly takes responsibility for converting tagged RGB to the stated print condition, record that instruction; if the brief only requests tagged RGB, leave conversion responsibility open and ask. A profile in the output settings does not by itself assign that responsibility.

## Sources

- Norm: [ISO 15930-7:2010, edition 2](https://www.iso.org/standard/55843.html), complete PDF/X-4 and external-profile PDF/X-4p exchange; `verify` clause for specific box and output intent requirements.
- Tool: Adobe InDesign Help, [Adobe PDF export options](https://helpx.adobe.com/indesign/desktop/save-export-and-publish/save-and-export/adobe-pdf-export-options.html), Marks and Bleeds and Output; `verify` installed version.
- Project specification: printer’s job brief supplies dimensions, marks, finishing and color policy. The postcard dimensions are example values.
