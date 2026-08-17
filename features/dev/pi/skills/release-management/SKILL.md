---
name: release-management
description: Turn an approved, reviewed change into a versioned release. Use after code review and documentation consistency when shipping a version. Produces a semantic version decision, changelog entry, release notes, and a release tag.
---

# Release Management

A release is a promise with a version number. The version communicates the blast radius of a change; the changelog records what changed; the release notes tell users what matters. Skip any of these and the promise is unreadable. This skill sits between the review gates and deployment: it turns an approved change into a shippable artifact with a name.

## Theoretical Foundation

- **Semantic Versioning** (Preston-Werner 2011): MAJOR.MINOR.PATCH. MAJOR for incompatible API changes, MINOR for backward-compatible features, PATCH for backward-compatible fixes. The version number is a contract with consumers.
- **Keep a Changelog** (Lacoste 2017): A curated, human-readable list of notable changes per release — not a raw commit dump. Sections: Added, Changed, Deprecated, Removed, Fixed, Security.
- **Conventional Commits** (2019): Structured commit messages (`feat:`, `fix:`, `BREAKING CHANGE:`) enable mechanical changelog generation and version inference. Consumes the history produced by `commit-pr-hygiene`.
- **Release Engineering** (Humble & Farley 2010): Releases are repeatable, automated, and low-ceremony. A release that depends on one person's memory is a liability, not a process.

## Trigger

Load this skill when:
- `code-review` is APPROVE and `documentation-consistency` has passed
- The change ships as a versioned release (library, application, service with a version tag)
- The user asks to "cut a release", "bump the version", or "write the changelog"

Do NOT load this skill for:
- Continuous/rolling deployment with no version surface
- Internal-only changes with no consumer of a version number

## Process

### Step 1: Determine Release Scope

```
1. git log <last-tag>..HEAD — every commit since the previous release
2. Classify each commit:
   - feat → user-visible feature
   - fix → bug fix
   - BREAKING CHANGE / ! → incompatible change
   - docs, chore, refactor, test → not user-visible (changelog: omit or group)
3. Identify breaking changes explicitly — they drive the MAJOR decision
```

### Step 2: Decide the Version

```
SemVer:
- Breaking change present → MAJOR (x+1).0.0
- Only new features      → MINOR x.(y+1).0
- Only fixes/docs        → PATCH x.y.(z+1)

Pre-1.0 policy (if the project uses one):
- 0.x.y: breaking → 0.(x+1).0; features → 0.x.(y+1); fixes → 0.x.(y+1)
  (record the project's actual pre-1.0 convention — do not impose SemVer on a 0.x project)

Record the decision and its rationale. The rationale is part of the release record.
```

### Step 3: Write the Changelog

```
Keep a Changelog format:
## [X.Y.Z] - YYYY-MM-DD
### Added
- ...
### Changed
- ...
### Fixed
- ...

Rules:
- One line per user-visible change, linked to commit/PR where possible
- Group by section, newest release at top
- Move the "Unreleased" section (if present) into the new version header
- Never dump raw `git log` — curate
```

### Step 4: Write the Release Notes

```
Release notes are for humans; the changelog is the exhaustive record.

Release notes answer:
- What changed (the signal, not every commit)
- Why it matters to the user (impact, not mechanics)
- Migration / upgrade steps (breaking changes: exact steps to adapt)
- Known risks or limitations

Audience: the person deciding whether to upgrade. They read the notes, not the changelog.
```

### Step 5: Tag and Publish

```
1. Create an annotated tag matching the version:
   git tag -a vX.Y.Z -m "Release X.Y.Z: <summary>"
2. Verify the tag points at the approved commit (not a later, unreviewed one)
3. Push the tag — this is the release trigger
4. Confirm the release pipeline sees the tag
```

## Evidence

After completing this skill:
- [ ] Release scope enumerated (commits classified)
- [ ] Version decision recorded with rationale
- [ ] Changelog updated (Keep a Changelog format)
- [ ] Release notes written (user-facing)
- [ ] Tag created, verified against the approved commit, and pushed

## Exit Gate

Release management is complete when:
- The version, changelog, release notes, and tag are mutually consistent
- The tag references the approved commit
- The release is ready for `integration-deployment`

## Handoff

After this skill:
- **`integration-deployment`** — deploy the release to staging/production

## Anti-Patterns

- **Changelog from commit dump**: `git log` pasted into CHANGELOG.md. It is noise, not signal. Curate.
- **Version bump without breaking-change analysis**: Bumping MINOR because "it feels bigger" without checking whether anything actually broke the contract.
- **Release notes = changelog**: Pasting the changelog into the release notes. Different audiences, different content.
- **Tagging before review**: Tagging a commit that hasn't passed `code-review` and `documentation-consistency`. The tag is a promise of quality.
- **Inconsistent release policy**: Cutting a release for one fix but not another of equal size. Pick a policy (e.g., "every merge to main is releasable") and hold it.
