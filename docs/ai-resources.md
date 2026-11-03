# AI resources

`my.features.ai.resources` is the shared, runtime-neutral policy and skill tree for interactive
coding runtimes. The feature is disabled by default; a host enables it and names the consumers that
receive it.

## Source and layout

```
features/ai/resources/
  nixos.nix              enable option and consumer binding
  lib/default.nix        discovery, IDs, ordering, duplicate detection
  policies/
    common/              neutral policy for every consumer
    opencode/            OpenCode-specific surface
  skills/
    <id>/SKILL.md        native skill; supporting files stay beside it
```

The two trees are the source. There is no manifest to keep in step:

- Every regular `.md` or `.markdown` file under `policies/<namespace>/` is one instruction fragment.
  Its ID is `<namespace>/<path without extension>`; `common/00-scope` and `opencode/00-scope` are
  therefore distinct resources. Two files that resolve to the same ID fail the evaluation instead of
  being silently resolved by the consumer's precedence.
- A directory containing `SKILL.md` is one skill; it is not searched for more skills. A root-level
  `<id>.md` is a flat skill. Supporting `references/`, `scripts/` and assets stay in the tree and are
  referenced relative to the directory containing `SKILL.md`. Skill IDs are path-derived, sorted and
  rejected on duplicates, matching OpenCode's own discovery rule.
- A directory without `SKILL.md` is a grouping directory, not an empty skill. No empty directory is
  required anywhere.

Discovery runs on content-addressed copies (`builtins.path`), so a document outside these trees does
not move the store path, and a changed policy or skill does. The whole tree is copied, so relative
references inside a skill keep working.

## OpenCode binding

The OpenChamber consumer passes the native keys through `OPENCODE_CONFIG_CONTENT` on the
`openchamber` service:

```json
{
  "instructions": ["/nix/store/…/policies/common/00-scope.md", "…"],
  "skills": ["/nix/store/…/ai-resources-skills"]
}
```

Both entries are absolute. OpenCode resolves a relative `skills` entry against the active working
directory, which makes a project-dependent load order; the absolute path keeps the managed tree
independent of the session's cwd.

`OPENCODE_CONFIG_CONTENT` is a config document, not a replacement. OpenCode combines the
`instructions` and `skills` arrays from every loaded document. OpenChamber's managed file
(`opencode.managed.json`, selected by `OPENCODE_CONFIG`) continues to own `plugins` and
`permissions`, and the user's global and project configuration continues to own its own values and
skills. This module does not set `OPENCODE_CONFIG`, does not write a user config file, and does not
write `/etc/opencode`.

The managed paths are in the Nix store and are read-only. A UI may list them as native skills;
editing one must fail rather than write to the store. User-created skills and settings stay outside
this namespace.

## Lifecycle

- Add a policy fragment: add the Markdown file under the owning namespace and gate the change. The
  new ID appears in the next OpenCode config load.
- Add or remove a skill: add or remove its directory under `skills/`; the content-addressed tree and
  the rendered `skills` path change together. No registry or list is edited.
- Retire the feature: disable it on the host. The managed config content disappears from the service
  environment; user configuration and OpenChamber's own managed file are untouched.

A future runtime adds a namespace under `policies/` and a consumer that selects `common` plus that
namespace. `common` is the neutral layer; a runtime-specific fragment never belongs in `common`.

## OpenClaw is not a consumer

The Gateway's delegated-work policy remains
`features/services/openclaw/gateway/policy/AGENTS.md`, rendered into the Gateway workspace by the
Gateway module. This tree does not replace it, move it, or claim a single source for both runtimes.
Adopting the tree for OpenClaw is a separate change that must prove the OpenClaw instruction
contract first; the resources are formatted so that change can reuse them without OpenClaw-specific
metadata.
