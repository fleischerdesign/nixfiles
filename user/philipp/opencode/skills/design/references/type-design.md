# Type Design

## When to load & job

Lead with Type Design when the work changes the font itself: variation axes, glyph outlines or behavior, spacing, kerning or OpenType features. This is a prototype: make a small experimental font or a specimen that isolates a drawing or shaping decision. If existing faces and features can do the job without modifying a font, lead with Typography instead. Full family development, engineering and release belong to a type designer or font engineer.

## Inputs & concepts

Get editable sources and modification rights from their owner, plus the subset and scripts, target sizes, target applications, current masters, build toolchain and feature definitions. Ask whether an experimental binary can be shared at all. If sources or rights are missing, demonstrate the mechanism with an explicitly licensed sample and label it as a substitute; do not modify the project font.

An axis is a dimension of variation with user-facing coordinates; a named instance identifies a particular location. Masters provide source drawings and metrics; intermediate output depends on point correspondence, not merely on similar silhouettes. **Advance width** governs how far text progresses after a glyph; **sidebearings** describe space around its drawing and shape the default rhythm. **Kerning** adjusts particular neighbors or groups in context. OpenType separates substitution (`GSUB`, such as localized forms) from positioning (`GPOS`, such as pair adjustments). A language-specific feature needs a correctly tagged text run and a shaping environment that applies it.

## Decisions & procedure

- **Continuous axis or discrete styles.** Use variation when the intermediate drawings do a real job, such as fitting headline widths. Discrete styles are simpler if only a few voices matter. Variation requires corresponding geometry and may need another master where the design changes character.
- **Spacing or pair adjustment.** Change a sidebearing if a glyph leaves the same hole beside many neighbors; the change affects all its contexts. Use class kerning for a shape relationship and a pair exception for an outlier. Compare control strings and words across weights rather than tuning around one headline.
- **Language behavior or opt-in expression.** Use `locl` for localized forms dictated by the tagged language. Keep a stylistic alternate opt-in when it changes expression rather than language; the alternate then depends on the application's available controls.

1. Build a **glyph-and-context worksheet**: list affected glyphs, strings, languages, axis locations or feature states, and the observed problem. Add neighboring glyphs or unmodified strings that make changed spacing visible. Use [Type setting](knowledge/type-setting.md) (`references/knowledge/type-setting.md`) to put the prototype in realistic text roles and renderers rather than presenting outlines alone.
2. Edit the smallest source slice that demonstrates the decision. For variation, compare contour order, direction, start points and matching on- and off-curve points across sources before adding an intermediate master. For spacing, establish default widths and sidebearings before editing kerning; for substitution, name the scripts and language systems to which the rule applies.
3. Build a separately named experimental binary with the project's toolchain and record the source revision and build command. Compose the same text at the extremes and a meaningful intermediate location, or with the relevant feature states and language tags. Pair the in-use specimen with an outline or spacing diagram that explains the source change.

## Worked example & typical mistakes

A light and bold `O` look correct at their masters, but the counter pinches midway. In the worksheet, draw correspondence lines between inner contour points. The first point in one master sits at the top and in the other on the right, so the interpolation pulls corresponding segments diagonally. Align start points and point order without changing the visible master shapes. Show the same interpolated location again in `HOOH` and a headline. If the opening now stays coherent but still needs optical tuning, that is a separate drawing decision.

Adding a middle master to hide mismatched correspondence can move the deformation to another interval. Repair the pairing first and add a master only when the intended intermediate shape is genuinely different.

## Standards, limits & handover

The Microsoft [OpenType 1.9.1 specification](https://learn.microsoft.com/en-us/typography/opentype/spec/) defines binary tables and behavior: see `fvar`, `gvar` for TrueType glyph variation, `GSUB`, `GPOS`, and the registered `locl` feature. Tool behavior is separate: see the fontTools [varLib documentation](https://fonttools.readthedocs.io/en/latest/varLib/index.html) for building variations; `verify` the installed version and source format. Control strings are a design convention, while script coverage and target apps are project choices.

Provide source, permitted binary, build notes and specimens with coordinates, language tags or feature states. Ask which intermediate values, scripts and apps matter. A type designer or font engineer owns broader coverage, rendering proofs and release; a narrow prototype does not represent the rest of the family.
