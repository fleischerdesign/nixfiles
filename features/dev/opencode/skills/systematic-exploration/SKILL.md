---
name: systematic-exploration
description: Methodical codebase investigation. Use before forming opinions — read the relevant code, trace dependencies, map the affected module graph before spec-first or architecture-design. Produces a structured exploration report with file paths, module boundaries, and known unknowns. Never guess what the code does — go look.
---

# Systematic Exploration

You do not form opinions about code you haven't read. Before writing a spec, proposing an architecture, or fixing a bug, you must understand the existing system well enough to predict how your change will interact with it. Exploration is not procrastination — it is the prerequisite for every other skill.

## Theoretical Foundation

- **Self-Documenting Investigation** (Hunt & Thomas 1999, *The Pragmatic Programmer*): Code is the only reliable source of truth. Design docs rot, comments lie, but the execution path is always honest. Your exploration must be grounded in the running code, not the documented intent.
- **Context Window Economics**: Every byte of tool output costs reasoning capacity. Use context-mode tools (ctx_execute, ctx_execute_file) to process large outputs in sandboxes and surface only the derived answer. Never read raw output you intend to filter or transform.
- **Parallel Search**: Independent queries — different files, different symbols, different modules — must be executed in parallel (batch tools, not sequential). Sequential searching is the most common exploration inefficiency.

## Trigger

Load this skill when:
- You are about to run `spec-first` but haven't read the relevant code yet
- A bug report references code you haven't seen
- You are asked "how does X work?" or "where is Y defined?"
- You need to understand module boundaries before proposing an architecture change
- The user says "look at," "explore," "find," "search for," or asks about code structure

Do NOT load this skill for:
- Looking up a single known file path — just read it directly
- Tasks where the exploration target is trivially known from recent context
- Pure implementation tasks where the spec already cites exact locations

## Subagent Delegation

For investigations spanning 2+ modules or an unfamiliar area, dispatch explore subagents for parallel reconnaissance:

```
task({
  subagent_type: "explore",
  prompt: "Search for [specific target]. Look in [directories]. Search breadth: [quick/medium/very thorough]. Report back: [specific questions to answer].",
  description: "Explore [area]"
})
```

Dispatch one explore subagent per independent search area in parallel (single message, multiple `task` tool calls). The parent synthesizes findings — subagents provide raw data, not judgments.

Do NOT delegate when:
- The search is a single known file or directory
- The area is small enough to read directly in < 3 tool calls
- You need real-time interaction with the findings to choose the next search target

## Process

### Step 1: Define the Investigation

Before any tool call, articulate exactly what you need to learn:

```
1. What is the QUESTION? (one sentence)
2. What do I ALREADY know? (from context, prior sessions, common patterns)
3. What are the CANDIDATE locations? (directories, file patterns, symbol names)
4. What would constitute SUFFICIENT evidence? (stop condition — when do I know enough?)
```

A precise stop condition prevents infinite rabbit holes. "Understand error handling" is not a stop condition. "Identify every call site of `validateSession` and map their error propagation paths" is.

### Step 2: Parallel Search

Execute independent searches simultaneously:

```
Tool calls in a SINGLE message (parallel):
- grep("pattern1", path="src/")
- grep("pattern2", path="src/")
- read("src/module-a/index.ts")
- glob("src/**/auth*.ts")
```

Sequential searching — running grep, reading the output, running another grep — is the most common exploration slowdown. If you know the search terms upfront, batch them.

### Step 3: Trace Relationships

After locating relevant code, trace the dependency graph:

```
1. What does this module IMPORT?
2. What IMPORTS this module? (reverse dependency check)
3. What INTERFACES does it expose? (public API surface)
4. What KNOWLEDGE does it hide? (implementation secrets — Parnas 1972)
5. What TESTS exercise it? (test coverage reveals expected behavior)
```

A module is understood when you can describe: what it depends on, what depends on it, what it exposes, and what it keeps private.

### Step 4: Process Large Outputs in Sandboxes

When tool output would exceed ~500 lines, process it in a sandbox rather than reading it raw:

```
// Instead of reading a 2000-line log or search result directly:
ctx_execute(language: "javascript", code: `
  const results = FILE_CONTENT.split('\n');
  console.log(results.filter(l => /pattern/i.test(l)).slice(0, 30).join('\n'));
`)
```

This keeps the raw bytes out of context and the derived answer in. Every byte you read into context is a byte you can't use for reasoning.

### Step 5: Synthesize

Compile findings into a structured report:

```
1. Investigation summary (one paragraph — what was the question?)
2. Key locations (file:line for each important finding)
3. Module map (which modules are involved, what they depend on)
4. Known unknowns (what you couldn't determine — e.g., "runtime config path is unclear")
5. Impact assessment (how a change in this area would ripple through the system)
```

The report is the evidence packet for the next skill in the chain — usually `spec-first` or `systematic-debugging`.

## Evidence

After completing this skill:
- [ ] Investigation question and stop condition defined
- [ ] Key locations identified with file:line references
- [ ] Dependency graph traced (imports, reverse imports, interfaces)
- [ ] Large outputs processed in sandboxes (not read raw)
- [ ] Known unknowns explicitly listed
- [ ] Structured exploration report ready for handoff

## Exit Gate

Exploration is complete when:
- You can describe every module relevant to the investigation — its interface, its dependencies, and its secrets
- Known unknowns are explicit (not "we'll figure it out later" but "the config binding happens at runtime in an env-dependent way — we'll need to test against staging")
- The report provides enough evidence for the next skill to begin without repeating the exploration

## Handoff

After this skill, the next step is one of:
- **`spec-first`** — write the specification for a new feature or fix
- **`architecture-design`** — propose structural changes based on exploration findings
- **`systematic-debugging`** — if the exploration revealed the bug's location but not its cause

## Anti-Patterns

- **Exploration without stop condition**: "Let me just look around" with no specific question. You will read indefinitely without producing a report.
- **Sequential search**: grep, read output, think, grep again, read output, think... Each round trip costs a tool call and burns context. Batch independent queries.
- **Reading raw large output**: A 2000-line grep result read directly into context wastes your reasoning capacity. Process in sandboxes.
- **Exploration as procrastination**: Reading one more file when you already have enough evidence to start `spec-first`. The report doesn't need to be exhaustive — it needs to be sufficient.
- **Guessing locations**: "It's probably in src/utils" without checking. Use glob and grep to find the actual location, then read it.
- **Ignoring tests**: The test suite is the most reliable documentation of expected behavior. Read tests before forming opinions about what code "should" do.
