# dsh Feature — Agent Handbook

Declarative NixOS/Home-Manager integration for DeepSeek Harness (dsh), the
open-source agent harness by DeepSeek AI. Everything is a Cordis plugin —
including the web UI, the LLM adapters, and MCP clients.

## File Map

| File | Role |
|---|---|
| `default.nix` | Feature module: system-level options + user-level `home-manager.sharedModules` |
| `lib/render.nix` | Pure renderers: options → dsh documents (settings.yaml, cordis.patch.yml, credentials, profile manifests) |
| `lib/plugins.nix` | Plugin auto-discovery + generated `plugins.<name>.enable` options |
| `plugins/<name>/manifest.json` | Plugin version pin (same convention as `packages/custom`) |
| `plugins/<name>/package.nix` | Plugin derivation |

The dsh package itself lives in `packages/custom/dsh/` (pnpm-workspace build
from upstream GitHub releases). See `docs/upstream-build.md`.

## Architecture

```
hosts/<name>/configuration.nix                 ← user-facing config
  my.features.dev.dsh.{credentials,deepseek,piAi,defaultModel,persona,mcpServers,profiles,settings}
        │
        ▼
features/dev/dsh/default.nix                   ← options + wiring
  ├── sops.templates."dsh-credentials.yaml"    ← mode 0600
  ├── renders via lib/render.nix
  └── home-manager.sharedModules               ← per-user materialization
        ├── ~/.dsh/settings.yaml               ← Store symlink (JSON ⊂ YAML)
        ├── ~/.dsh/cordis.patch.yml            ← home patch layer
        ├── ~/.dsh/.credentials.yaml           ← out-of-store sops symlink
        ├── ~/.dsh/node_modules/<plugin>       ← plugin injection
        └── ~/.dsh/profiles/<name>/{package.json,cordis.patch.yml}
```

dsh resolves configuration at request/boot time; no restarts for settings
changes (hot reload).

The web server can run as a background service via `web.enable = true`
(`systemd.user.services.dsh-web`), and automatically registers a native desktop
app via `my.features.desktop.webapps.apps.dsh` on non-server hosts.

Agent self-improvement uses the `~/.dsh/incubator/<plugin-name>/` directory,
explained to the agent via `features/dev/dsh/AGENTS-PROMPT.md` (materialized as
`~/.dsh/AGENTS.md`). Stable incubator plugins can be promoted to permanent
declarative plugins under `features/dev/dsh/plugins/<name>/`.

## Critical Invariants (read before extending)

1. **`agent-default-model` is a settings namespace, not a patch row.** The
   dsh-base bundle already inserts that composition row; a second insert with
   the same id fails the boot (`duplicate loader entry id`). The default model
   belongs in `settings.yaml`.
2. **Patch rows replace whole `config`** (no merge). Override existing
   bundle rows by `id` without `insert` (last write wins per row).
3. **Credentials use the `refs` section** (flat `ENV_NAME → secret`), never
   `records` (those are `<scope>/<id>` Models-UI sign-in data). The option
   type must be `attrsOf (submodule { key })` — a plain `attrsOf str`
   type-checks eagerly and creates an infinite recursion with
   `config.sops.placeholder`.
4. **Plugin injection goes to `~/.dsh/node_modules/`, never
   `~/.dsh/profiles/node_modules/`.** The launcher heals the latter itself
   (mkdir/link) and an HM-managed read-only directory there crashes the boot
   with `EACCES`. `.dsh/node_modules` sits on the same Node parent-walk and is
   never written by the launcher.
5. **Secrets never enter settings** — only credential references
   (`apiKeyEnv = "DEEPSEEK_API_KEY"`); values resolve from the credential
   store per request.
6. **Render only genuine overrides.** Every rendered field replaces the
   upstream schema default; omitted fields inherit. Dormant namespaces render
   as absent.

## Plugin System

Adding a plugin = one new directory under `plugins/`, zero registration.
Discovery, package build, user-profile injection, bundle activation, and
updater coverage are automatic. Full walkthrough: `docs/plugins.md`.

In-tree bundles (`@deepseek-ai/dsh-*`, ~45 shipped) are activated/configured
declaratively via `my.features.dev.dsh.profiles.<name>.patches`.

## Verification Workflow

```bash
nixfmt <changed .nix files> && deadnix --fail <files> && statix check
nix flake check                     # eval all 5 hosts + gates
nix build .#dsh                     # package build
# Boot smoke test (stable server = timeout kill, exit 124):
OUT=$(nix build .#dsh --print-out-paths --no-link | tail -1)
DSH_HOME=$(mktemp -d) timeout 40 $OUT/bin/dsh web --no-open
# Verify rendered documents inside the HM generation:
DRV=$(nix eval --raw .#nixosConfigurations.jello.config.home-manager.users.philipp.home-files.drvPath)
nix build "$DRV^*" --no-link --print-out-paths | tail -1
```

Boot-log gates: zero `failed to import`, `EACCES`, `duplicate loader entry`,
`must be`.

## Deep Dives

| Doc | Content |
|---|---|
| `docs/config-surfaces.md` | Option → document mapping, namespace vs. patch-row decision rule |
| `docs/plugins.md` | Plugin packaging walkthrough (community + in-tree activation) |
| `docs/upstream-build.md` | dsh package build internals, update procedure, gotchas |
| `docs/distributed-agent-mesh.md` | Formal distributed architecture: Hermes ↔ DSH mesh, 2PC worktrees, leases, OCAP |
| `docs/multi-tenancy.md` | Multi-Tenant Agent Architecture: LBAC lattices, process isolation, quota enforcement |
| `docs/runtime-vs-declarative-state.md` | Dual-state coherence model: reconciling declarative NixOS policy with autonomous runtime state |
| `docs/cross-repository-synthesis.md` | Cross-Repository Semantic Graph Synthesis (CRSGS) & Multi-Repo Two-Phase Commit (MR-2PC) |
| `docs/memory-architecture.md` | Agentic Memory: OSS evaluation (Mem0, Letta, Zep, Cognee) & bitemporal 3-tier NixOS model |
| `docs/event-ingress-and-webhooks.md` | Reactive Trigger Mesh: CloudEvents, HMAC, debouncing alert storms, local journal ingress |
| `docs/ui-ux-architecture.md` | UI/UX Architecture: Slot composition, MR-2PC approval inspector, mesh status & graph HUD |
| `docs/formal-foundations-and-invariants.md` | Formal Foundations: CoW-OverlayFS OCC, Risk Lattices (R0-R2), AGM Belief Revision & Biscuit Mesh |
| `/etc/nixos/docs/dsh/dsh-slot-inventory.md` | Complete DSH Client SlotMap Inventory: Scopes, kinds, and injection surfaces across all UI packages |
