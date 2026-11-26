# Data Visualization

## When to load & job

Use this when the deliverable is a chart, an annotated data graphic, or a set of views built from data. Start with the comparison a reader needs to make, not the chart type you want to draw. If the job is to explain a procedure rather than a measured relationship, use information design. Produce a chart from the supplied data, or an annotated wireframe with blank plotting areas when the data are unavailable.

## Inputs & concepts

Get source rows and their definitions, time coverage, units, denominators, category membership, and the expected observations from the data owner. Ask what missing, suppressed, and zero values mean and whether a definition changed during the period. Get intervals and their interpretation from the source analysis. Bring the intended display size, the filters readers can use, and the decision the reader will make. Don't invent series, sample sizes, or bounds for a sketch.

The **grain** is what one row stands for: a site visit, a site and month, or a whole region and year. A **measure** is what the chart reports at that grain; a rate takes its meaning from both the numerator and denominator. A **mark** is the drawn object and a **channel** is the way it encodes a field, such as position or length. A **domain** is the span of source values shown on a scale. A **series** is a set of observations the chart treats as related; a series break can carry meaning, not just signal a drawing problem.

## Decisions & procedure

The primary decision is which comparison the chart must make easiest; a secondary question that needs a different unit, baseline, or population gets its own view rather than sharing one scale. A definition change — a new denominator, observation window, or measured event — creates a new series even when the field name and units match; never connect across the boundary without saying so. Record both in the plot contract. Translate the comparison into marks, scales, missing observations and supplied uncertainty with [Data encoding](knowledge/data-encoding.md) (`references/knowledge/data-encoding.md`); this entry does not repeat that method.

1. Write the primary reader question and name the grain, population, time window, and unit of the answer. If a secondary question needs a different unit or baseline, give it a separate view rather than making one scale answer both.
2. Draft a **plot contract**: source fields, any approved transforms, definition of each series, annotation copy, and what changes when a query changes. Use the data-encoding method to translate the comparison and observation states into marks and scales.
3. Build the chart at delivery size. Tie plot labels and source notes to the plotted population, not just the enclosing dashboard. If filters can exclude all observations, show the resulting scope and its empty state instead of leaving the previous plot visible.
4. Use [Accessibility](knowledge/accessibility.md) (`references/knowledge/accessibility.md`) to provide an equivalent for the comparison and exact lookups, with the equivalent following the same filter selection as the graphic.

## Worked example & typical mistakes

In an illustrative wait-time report, the data owner supplies median wait from arrival to triage through June and median wait from arrival to first clinical contact starting in July. The table calls both fields “median wait.” Even though the units and date sequence match, the plot contract gives them different series keys and records the event that ends each clock. Place them on one timeline with no connecting segment at the boundary and label the definition change there. This still shows the reporting history, but doesn't turn a difference between two measures into an increase in one. If the question is whether triage wait improved after June, the supplied data cannot answer it.

Filling an unreported month with zero makes a library draw a drop and rebound that never happened. Keep the month in view without a value, and annotate it there rather than burying its meaning in a general note.

## Standards, limits & handover

Cleveland and McGill's [“Graphical Perception”](https://doi.org/10.1080/01621459.1984.10478080) (1984) studies elementary judgments such as position on a common scale; it informs encoding conventions, not universal chart rules. D3's [line generator, `line.defined`](https://d3js.org/d3-shape/line#line_defined) documents how an undefined point breaks a path (`verify` installed `d3-shape` version); an omitted row cannot trigger that branch. For web output, W3C [WCAG 2.2](https://www.w3.org/TR/WCAG22/) (Recommendation, 12 December 2024), SC 1.1.1 covers alternatives to non-text content and SC 1.4.1 addresses reliance on color alone.

Show the chart at delivery size with units, source, coverage, and any consequential definitions. The analysis owner supplies aggregation, disclosure rules, and the interpretation of bounds; chart geometry cannot establish causality or resolve changes in measurement. Ask whether the human needs absolute magnitude, change from baseline, or both in different views.
