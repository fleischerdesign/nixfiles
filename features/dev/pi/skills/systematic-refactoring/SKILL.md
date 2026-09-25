---
name: systematic-refactoring
description: Restructure working code while preserving intended behavior and compatibility. Use for changes across responsibilities, interfaces, or callers; skip mechanical formatting and trivial renames.
---

# Systematic Refactoring

Refactoring changes structure without silently changing intended behavior. Keep the scope coherent
and use the project's existing checks as evidence.

## Procedure

1. Define the structural improvement and the behavior or interfaces that must remain stable.
2. Locate callers, public boundaries, related configuration, and existing checks.
3. Add targeted characterization coverage only where behavior is uncertain and the coverage provides
   useful protection.
4. Make small coherent edits and validate at useful checkpoints. Separate unrelated behavior changes
   from the structural change.
5. Use expand–contract when consumers cannot migrate atomically. For coupled internal callers, a
   coordinated update is simpler and clearer.
6. Inspect references and the final diff, run checks appropriate to the changed surface, and report
   any deliberate behavior difference separately.

## Good practice

- Prefer reversible transformations and preserve existing user work.
- Search for callers rather than assuming an interface is private.
- Do not require a commit, test, or migration pattern when the repository or change does not need it.
- `git diff -w` can help inspect whitespace noise; it is not proof that behavior is unchanged.
