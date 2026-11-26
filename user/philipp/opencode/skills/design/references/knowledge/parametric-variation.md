# Parametric variation

## Use when

A rule should generate a family of artifacts, and the next decision is which controls to expose and where their interactions become visible. Produce a dependency map, parameter sheet, and reproducible contact sheet from a targeted sweep.

## Inputs

Get the properties the family should retain, the intended differences, output size or physical units, and any process limits from the project or supplier. Bring the generator, data, runtime version and assets. Label exploratory parameter ranges separately from measured or specified bounds. Without production limits, show a formal study with provisional ranges and leave material behavior open.

## Procedure

1. Separate fixed rules, independent controls, derived quantities and stochastic choices. Draw the dependency chain to the output: for example, pitch determines column count, which determines available margins. Expose pitch or column count as an independent input, not both, unless you define which takes precedence.
2. Give each control units or categories, a reference value, a meaningful exploratory range, and its interaction with fixed constraints. Note discrete transitions, such as the next whole motif fitting the panel, and describe how the generator handles conflicting inputs. If a supplier specifies only certain increments, sweep those increments rather than an arbitrary continuous range.
3. Record a seed with the control set, generator and runtime versions, and input assets. Reset each stochastic source used by the sketch. Separate random streams or derive values from stable element IDs when unrelated edits should not reroll existing elements. Seeding a sequence does not preserve element identity if the order of draws changes.
4. Sweep one control against the reference with seed and other inputs fixed; include endpoints and points around a suspected transition. Sweep seeds separately at one control setting. Where the dependency map suggests a coupling, cross selected values of those controls using the same seeds across variants. Arrange comparable crops side by side and label the changed control, the visible consequence and the settings needed to reproduce it.

## Limits

A sweep samples the chosen space; unshown combinations can behave differently. Repeatability also depends on the algorithm, version, inputs, and use of time or other state. A derived layout bound is a model constraint, not a production specification. Process tolerances and material performance need supplier evidence or physical trials.

## Worked example

In an illustrative repeat-pattern editor, increasing pitch means fewer columns fit the printed panel. With the sketch's existing random sequence, changing the count also changes motifs in later rows. The designer keys motif identity to seed and stable row and column IDs, then renders pitches just before and after the count changes. The contact sheet now isolates the disappearing column and the redistribution of edge space. A second row varies the seed at fixed pitch to show motif diversity without disguising the edge behavior.

## Sources

- Przemysław Prusinkiewicz and Aristid Lindenmayer, [*The Algorithmic Beauty of Plants*](https://algorithmicbotany.org/papers/#abop) (1990): rule-based and stochastic generation through L-systems; exact section `verify`.
- p5.js reference: [`randomSeed()`](https://p5js.org/reference/p5/randomSeed/) and [`noiseSeed()`](https://p5js.org/reference/p5/noiseSeed/), respectively for random sequences and noise values. Installed version `verify`; the calls are not a general guarantee of reproducibility across versions or renderers.
