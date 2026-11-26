# Data Visualization

## When to load & job

Use this when the deliverable is a chart or a set of views built from data. Start with the comparison a reader needs to make, not the chart type you want to draw. If the job is to explain a procedure rather than a measured relationship, use information design.

## Inputs

Bring the source data, units, denominators, time coverage, and definitions of suppressed, missing, and zero values. Get any interval estimates and their meaning from the data owner or the documented analysis. Without data, offer an annotated wireframe with empty plotting areas; don't invent series, sample sizes, or intervals to fill them.

## Decisions & process

- **Choose the mark from the comparison.** Use aligned dots or bars to compare values across categories. Use a line when change across ordered time is the point; its continuity helps readers see a trajectory but can imply observations between points. Show separate points if that implication matters.
- **Choose the scale from what the marks mean.** Start bars at zero because their length carries magnitude. To show small changes around a baseline, a line or dot plot with a clearly labeled tighter range can reveal the change but makes total magnitude less apparent. Keep comparable panels on a common scale unless showing each panel's local pattern matters more than comparing magnitudes.
- **Separate absence from uncertainty.** Break a line at missing observations and label the gap when the reason is known. Use supplied bounds when uncertainty affects the comparison: whiskers work for a few estimates; a band works across time but can crowd overlapping series. State what the bounds represent; don't invent a precision the source doesn't provide.

## Typical mistakes & examples

A dashboard fills an unreported month with zero so the library can draw a continuous line. Readers see a collapse and rebound that never occurred in the data. Leave the gap, distinguish it from observed zeros, and put the annotation at the affected month rather than hiding it in a general note.

## Deliverables & questions for the human

Show the chart at its intended size, with source, units, coverage, and any relevant annotations or definitions. Ask: Which comparison should the chart make easiest? Should the reader compare absolute magnitude, change from baseline, or both in separate views?
