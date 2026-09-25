---
name: systematic-debugging
description: Investigate failures or unexpected behavior when the cause is uncertain. Use to isolate competing explanations, gather evidence, and verify a targeted fix; skip for an obvious local correction.
---

# Systematic Debugging

Use an evidence-driven loop. The amount of process should match the uncertainty and impact of the
failure.

## Procedure

1. State the expected and observed behavior, relevant inputs, environment, and the complete error
   or log context.
2. Reproduce the behavior when feasible. For intermittent or environmental failures, use logs,
   instrumentation, controlled comparisons, or the smallest useful reproduction.
3. Identify plausible explanations and choose an experiment that distinguishes the leading ones.
   Update confidence from the result; a failed hypothesis is useful evidence.
4. Fix the narrowest responsible boundary. Inspect related occurrences when the evidence suggests a
   shared cause rather than applying a broad defensive patch.
5. Re-run the failing case and the relevant checks. Add regression coverage when it meaningfully
   protects the behavior and fits the project.
6. Report the cause, change, verification, and any remaining uncertainty.

## Good practice

- Keep observations separate from hypotheses and predictions.
- Preserve stderr and the original exit status when collecting command evidence.
- Do not claim a root cause merely because one patch makes the symptom disappear; connect the fix to
  an observed mechanism.
- If reproduction is impossible, say what evidence supports the diagnosis and what remains unknown.
- Do not automatically revert existing user work when a check fails; inspect the failure first.
