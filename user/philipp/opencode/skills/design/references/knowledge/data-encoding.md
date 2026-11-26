# Data encoding

## Use when

Turn a reader's comparison into a chart specification: what each row represents, which marks and scales carry the comparison, and how the chart shows missing observations and supplied uncertainty.

## Inputs

Get the source rows, field definitions, units, denominators, expected categories or reporting periods, and any grouping or aggregation rules from the data owner. Ask whether blanks mean not collected, not applicable, suppressed, or unknown; an absent row is only a gap if the source defines an observation expected there. For bounds, ask for their meaning, coverage level if applicable, and the estimate they describe. Without these inputs, an annotated chart skeleton can specify intended encodings but cannot populate a series or infer a missingness cause.

## Procedure

1. Write the comparison as a question: “Which site recorded more?” is a magnitude comparison; “When did counts change?” is a time comparison. Make an encoding sheet with one row per field or status: source field, meaning, mark or channel, scale, and visible annotation. Define the observation and denominator before turning counts into rates.
2. Assign the primary comparison to a common axis when possible. Use aligned dots for precise comparisons without implying an extent from zero, or bars when length from a baseline is the point. Set ordinary magnitude bars against zero; cutting off their base changes the apparent proportions. Use a line to carry change through ordered time when connecting observations makes sense, or separate dots when connections would imply more continuity than the source supports. Use labels or hue to identify categories, rather than making hue carry fine quantitative differences.
3. Declare the domain and units. Keep scales shared across panels meant for comparing magnitudes. For panels meant to reveal local variation, independently scaled dot or line panels can be useful; label their ranges so similar shapes are not mistaken for similar absolute changes.
4. Keep observed zero at its numerical position. Break a line at an expected but unavailable observation; retain the time slot and annotate its status without assigning it a height. Put supplied bounds on the same scale as the estimate: whiskers for isolated estimates or a band over adjacent periods when the bounds describe an ordered series and continuity is appropriate. Interrupt the band where bounds are unavailable. Name what the interval means next to the plot.

## Limits

These are encoding conventions and perceptual methods, not norms. A visible gap does not explain why a value is missing. Interval overlap alone is not a general method for inferring differences; the analysis owner determines what can be concluded. Suppression rules and rounding come from the project or source.

## Worked example

An illustrative count series contains January 4, February 0, March unreported, and April 5 with supplied bounds of 3–7. The time plot connects January to the observed zero in February and stops there. March stays on the axis with “Not reported”; April appears as a separate dot and whisker. If the source calls 3–7 a forecast range, label it as such rather than implying a confidence interval. If the comparison changes to “Which reported month had more?”, use a common-axis dot plot and keep March as a labeled row without a mark.

## Sources

- Cleveland and McGill, [“Graphical Perception”](https://doi.org/10.1080/01621459.1984.10478080) (1984), original research on elementary perceptual tasks, including judgment on common scales.
- Tamara Munzner, [*Visualization Analysis and Design*](https://www.cs.ubc.ca/~tmm/vadbook/) (2014), chapters 5, “Marks and Channels,” and 7, “Arrange Tables”; methods for mapping fields and comparisons to visual channels and arrangements.
