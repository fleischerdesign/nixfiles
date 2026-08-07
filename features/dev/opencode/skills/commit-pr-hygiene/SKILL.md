---
name: commit-pr-hygiene
description: Produce a reviewable, bisectable commit history and a well-structured PR. Use when splitting work into commits, writing commit messages, or preparing a pull request. Ensures the history is a narrative, not a log.
---

# Commit & PR Hygiene

The git history is the permanent record of how the system evolved. A well-crafted history answers "why was this changed?" without opening the code. A poorly crafted history answers nothing. Commit hygiene is not ceremony — it is the primary documentation that survives.

## Theoretical Foundation

- **Reviewability** (your Engineering Constitution): A 500-line diff is a process failure. Commits are the unit of review. If a commit cannot be reviewed in isolation, it is too large.
- **Bisectability**: When a bug is introduced, `git bisect` narrows it to a single commit. If commits mix unrelated changes, bisect points to a commit that contains both the bug and irrelevant noise — the noise obscures the cause.
- **Conventional Commits**: A structured message format (`type(scope): description`) that enables automated changelog generation and semantic versioning. Adopt when the project uses it; do not impose on projects that don't.
- **Atomicity**: A commit is a single, reversible unit of change. "Fix bug X AND refactor module Y" is two commits. If one needs to be reverted, the other shouldn't be caught in the blast radius.

## Prerequisite

Load **`project-onboarding`** first if commit conventions and commit hooks are unknown.

## Trigger

Load this skill when:
- Splitting completed work into commits
- Writing a commit message
- Preparing a pull request
- Reviewing commit history before pushing
- `tdd-discipline` triggers "commit after each step"
- `systematic-refactoring` requires "commit after each successful step"

Do NOT load this skill for:
- Work in progress that hasn't been verified (tests pass, review gate cleared)
- Single-commit changes with an obvious message
- Automated updates (dependabot, flake.lock) where the tool generates the message

## Process

### Step 1: Discover Repo Conventions

Before writing any commit message, determine the project's style:

```
1. Read git log: git log --oneline -30
2. Identify pattern:
   - Conventional Commits? (feat:, fix:, chore:, docs:)
   - Sentence case or lowercase? ("Add feature" vs "add feature")
   - Imperative mood? ("Add feature" vs "Added feature" or "Adds feature")
   - Issue references? ("#123" or "Closes #123")
   - Line length? (50/72 rule or free-form)
3. Check contributing guide: CONTRIBUTING.md, .github/CONTRIBUTING.md
4. Check commit hooks: .githooks/commit-msg (or husky, lefthook)
```

Match the existing style. Consistency with the project's history takes priority over personal preference or "best practice" from outside.

### Step 2: Size Commits

Split work into atomic, reviewable units:

```
Commit sizing rules:
- One logical change per commit. If the message needs "and" or a bullet list, split.
- A commit should change 1-3 files, <100 lines (typical). >200 lines: consider splitting.
- Every commit must leave the system in a working state (build passes, tests green).
- Refactoring commits: no behavior change. Feature commits: add behavior. Never mix.
- A commit that says "Fix A, fix B, and cleanup C" is three commits.

Commit sequence for a feature:
1. Refactoring (make the change easy) — verified green
2. Core implementation (the actual change) — verified green
3. Tests for the change — passed, evidence of correctness
4. Documentation updates — if applicable
```

### Step 3: Write the Message

```
Subject line (<72 chars):
  [type]([scope]): [imperative description]

Body (optional, wrapped at 72 chars):
  - Why this change is needed
  - What approach was chosen (if non-obvious)
  - Trade-offs or known limitations
  - Reference: issue, spec, ADR

Examples:
  feat(auth): add session token rotation
  fix(parser): handle empty input array without panic

Good subject line qualities:
- Imperative mood: "Add X" not "Added X" or "Adds X"
- Specific: "Handle null user in profile cache" not "Fix bug"
- Purpose-first: what the commit DOES, not what it TOUCHES
```

### Step 4: Structure the Pull Request

```
PR title: [Brief summary of the change, matching commit style]
PR body:
  1. What problem does this solve? (one paragraph)
  2. What approach was taken and why? (key decisions)
  3. How was it verified? (tests run, evidence)
  4. What are the risks? (backward compat, perf impact, migration needed)
  5. Reference: spec, ADR, issue numbers
  
Commit structure check (before marking ready):
- [ ] Each commit is atomic and green
- [ ] Commits are ordered logically (refactor → feature → tests)
- [ ] No "fixup," "wip," or "tmp" commits
- [ ] No unrelated changes in any commit
```

### Step 5: Self-Review Before Push

```
1. git diff --stat main..HEAD — check for unexpected files
2. git log main..HEAD — read every commit message; is each self-contained?
3. For each commit: does it compile? do tests pass? (if CI doesn't check per-commit)
4. Check for: secrets, debug logging, commented-out code, TODO comments without issue refs
5. git diff -w — any behavior changes where only structural change was intended?
```

## Evidence

After completing this skill:
- [ ] Commit convention identified from project history
- [ ] Commits are atomic and green
- [ ] Commit messages follow project style
- [ ] PR structured with problem, approach, verification, risks
- [ ] Self-review passed (no leaked files, no WIP commits)

## Exit Gate

Commit hygiene is complete when:
- Every commit can be reviewed in isolation (one change, one message)
- The PR tells a reviewer everything they need to assess the change
- `git bisect` would land on a meaningful, runnable commit — not a broken intermediate state

## Handoff

After this skill:
- **`code-review`** — the review is now lightweight because the history is self-documenting

## Anti-Patterns

- **Kitchen-sink commits**: "Add feature, fix typos, update config, and rename variables." Four separate changes in one commit. Now `git revert` for the typo reverts the feature too.
- **"git commit -am" with auto-message**: `git commit -am "fix stuff"` — the message tells nobody anything. You are writing for the developer who sees this commit in six months. That developer might be you.
- **Squashing without narrative**: Squashing all 37 commits into "Implement feature" loses the reasoning, the intermediate decisions, and the bisectability. Squash responsibly: preserve the narrative, compress the noise.
- **Imposing conventions**: Using Conventional Commits in a project that uses free-form messages. Match the project, not the textbook.
- **Fixing in the review commit**: Review catches a bug. You add a commit: "Address review feedback." That commit is a catch-all. Rebase: fold the fix into the original commit where it belongs, so the history shows the correct implementation, not the corrected implementation.
- **Commitless workflow**: Pushing one giant commit at the end of a day's work. If you can't split it, you don't understand what you changed. Understand it, then split it.
