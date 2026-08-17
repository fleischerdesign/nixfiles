---
name: project-onboarding
description: Discover project conventions without a pre-existing AGENTS.md. Use when entering a new repository to map build/test/lint commands, commit conventions, architecture, and contribution rules. Produces a structured project context summary that feeds every subsequent skill.
---

# Project Onboarding

You cannot apply rigorous engineering process to a codebase you don't understand. Onboarding is the systematic discovery of the project's conventions — the build system, the test runner, the commit style, the module graph — before you touch code.

## Theoretical Foundation

- **Convention over Configuration** (Ruby on Rails, Maven): Most projects encode their conventions in tooling configuration files (`package.json`, `Cargo.toml`, `flake.nix`, `Makefile`, `pyproject.toml`). Reading these files reveals the build/test/lint commands without guessing.
- **Self-Documenting Repositories**: In well-maintained projects, `AGENTS.md`, `CONTRIBUTING.md`, `README.md`, and `docs/` contain the onboarding narrative. In their absence, the git history and commit messages are the next-most-reliable source of convention.
- **The Principle of Least Surprise**: Before modifying code, you must know what the existing codebase considers "normal." Naming patterns, file organization, error handling style, and test structure are conventions you must match or deliberately change — never accidentally violate.

## Trigger

Load this skill when:
- Entering a new repository for the first time
- The project has no `AGENTS.md` or it is insufficient
- You cannot determine how to build, test, or lint the project
- The commit history style or PR conventions are unknown
- Any skill in the chain needs project context that hasn't been captured

Do NOT load this skill for:
- Repositories you've worked in recently (context is already established)
- Repos with comprehensive `AGENTS.md` that answers all questions
- Repos so trivial they have no build system or tests

## Process

### Step 1: Read Existing Guides

Read the project's onboarding files in priority order:

1. `AGENTS.md` — AI agent instructions (if it exists)
2. `CONTRIBUTING.md` or `.github/CONTRIBUTING.md` — contribution guidelines
3. `README.md` — project overview
4. `docs/architecture/overview.md` — architecture documentation (if it exists)
5. `docs/adr/` — architectural decision records (if they exist)

### Step 2: Discover Build, Test, and Lint Commands

Examine tooling configuration to determine commands:

```
Build:
  [file] → [inferred command]
  package.json → "npm run build" (if build script exists)
  Cargo.toml → "cargo build"
  flake.nix  → "nix build" or "nixos-rebuild"
  Makefile   → "make" or "make build"

Test:
  [file] → [inferred command]
  package.json → "npm test" (or specific test script)
  Cargo.toml → "cargo test"
  Makefile   → "make test"

Lint:
  [file] → [inferred command]
  package.json → "npm run lint" (if lint script exists)
  .eslintrc.* → "npx eslint <path>"
  pyproject.toml → "ruff check" (if ruff configured)
  flake.nix    → "nix fmt" (if formatter defined)
```

Also check: `.github/workflows/` for CI pipeline definitions — these are definitive for "what commands actually run."

### Step 3: Discover Commit Conventions

```
1. Read recent commit messages: git log --oneline -20
2. Identify convention: Conventional Commits? Free-form? Issue references?
3. Check for commit hooks: .githooks/pre-commit, .husky/, lefthook.yml
4. Check for commit message template: .gitmessage, .github/COMMIT_MESSAGE.md
5. Check pre-commit tooling: .pre-commit-config.yaml
```

If no convention is evident from the history and config, adopt the project's existing style (even if inconsistent). Do not impose your own style on a new repo.

### Step 4: Map the Module Structure

```
1. Top-level directories and their purpose:
   src/     → [main source]
   tests/   → [test suite]
   docs/    → [documentation]
   scripts/ → [build/CI scripts]

2. Entry points:
   [file] — main entry, invoked by [command]

3. Key dependencies:
   [library] — used for [purpose] (from [config file])

4. Module graph (if feasible):
   [module A] depends on [module B, module C]
```

### Step 5: Synthesize

Compile a structured context summary:

```
Project: [name from package.json/README/top-level]

Commands:
  Build: [command]
  Test: [command]
  Lint: [command]

Commit convention:
  Style: [Conventional Commits / free-form / described pattern]
  Hook: [pre-commit path or none]

Project type: [web app / CLI / library / NixOS config / ...]
Primary language: [language]
Package manager: [npm / cargo / nix / pip / ...]

Key modules:
  [module path] — [responsibility]

Known unknowns:
  [question not yet answered]
```

## Evidence

After completing this skill:
- [ ] Existing guides read (AGENTS, CONTRIBUTING, README)
- [ ] Build/test/lint commands documented
- [ ] Commit conventions identified
- [ ] Module structure mapped
- [ ] Structured context summary complete
- [ ] Known unknowns listed

## Exit Gate

Onboarding is sufficient when:
- You can build and test the project without guessing commands
- You know what the project's commit style is (or that it has none)
- You can locate any module's primary file within one glob/read
- Known unknowns are explicit, not undiscovered

## Handoff

After this skill, the next step is one of:
- **`systematic-exploration`** — deep dive into specific modules
- **`spec-first`** — write a specification with project context
- **`orchestration`** — feed context into the decision table

## Anti-Patterns

- **Skipping onboarding**: "I'll figure out how to build it when I need to." You'll build wrong, test wrong, and commit in the wrong style.
- **Tool assumption**: "It's probably `npm run build`" without checking `package.json`. Read the config file — 30 seconds to read beats 30 minutes of failed commands.
- **Changelog as architecture**: Reading the git log for 10 minutes without opening a single source file. The log shows what changed; the code shows what IS.
- **Exhaustive onboarding**: Trying to understand every file before writing any code. Onboard enough to be effective, then deepen as needed. The context summary is a starting point, not a PhD thesis.
- **Context-free execution**: Running build commands without understanding the project structure. If the build fails, you need to know which module failed and why — the context summary enables that.
