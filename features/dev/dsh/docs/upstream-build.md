# dsh Upstream Build

`packages/custom/dsh/` builds DeepSeek Harness from source. The workspace
layout **is** the runtime layout — this section records every non-obvious
decision and the traps discovered while making the build hermetic.

## Why the Full Workspace Is Deployed

Upstream is a pnpm-11 workspace monorepo (TypeScript, Node ≥ 22.19 / 24).
The CLI mounts `configTrees` with paths **outside** its own package
(`../../packages/preset/agent-presets/presets`), and the profile launcher
resolves bundles from the installation workspace. `pnpm deploy` pruning
would break both; the full built tree (`~1.7 GB`) is deployed under
`$out/lib/dsh`. Closure optimization is a documented Phase-2 candidate.

## Derivation Internals (`packages/custom/dsh/default.nix`)

| Aspect | Fact |
|---|---|
| Source | `fetchFromGitHub`, tag `dsh-v<version>` (`upstream.tagPrefix` in manifest.json) |
| Deps | `fetchPnpmDeps` with `pnpm = pnpm_11`, **`fetcherVersion = 4`** (mandatory for pnpm ≥ 11; version 3 was removed in nixpkgs 26.11). Top-level `fetchPnpmDeps`/`pnpmConfigHook` attributes — the `pnpm_11.fetchDeps`/`pnpm_11.configHook` package attributes are deprecated. |
| `env.HOME = "/tmp"` | pnpm `config set` writes need writable HOME |
| `npm_config_nodedir = ${nodejs_24}` | offline node-gyp against local Node headers |
| `preBuild`: `pnpm -r rebuild fs-ext koffi node-pty` | `pnpmConfigHook` installs with `--ignore-scripts`, so the three native addons upstream allowlists in `allowBuilds` never build during install. Without them the boot fails (`Cannot find module './build/Release/fs_ext.node'` for JSONL locking; node-pty for the web terminal). |
| `env.DSH_CLIENT_COMMIT_HASH = <7-char rev>` | the official build runs `git rev-parse HEAD` for browser metadata — no git in the sandbox → `spawnSync git ENOENT`. Inject the pinned tag commit. |
| Build | `pnpm run build` (tsc project refs + tsdown + web frontend), `NODE_OPTIONS` heap guard 8 GiB |
| Entry | wrapper: `node --expose-internals <out>/lib/dsh/apps/cli/lib/bin.js` |

### The `--expose-internals` Flag

The Cordis loader's builtin-module route (`vendor/loader/src/internal.ts`)
prefers `process.execArgv` containing `--expose-internals`; the fallback is
the prebuilt `node-addon-require-builtin` addon, which is not ABI-stable
across Node versions (fails on Node 24.19 with a V8 accessor error). HMR
(`cordis-plugin-hmr`, mounted for the live-reload `web` profile) hard-requires
loader internals. The wrapper flag is the stable route.

### `link-workspace-packages.mjs`

The published npm layout is flat; a pnpm workspace links packages
per-dependent. The Cordis loader imports workspace packages by bare name
from `vendor/loader`, whose ancestor `node_modules` chain ends at the tree
root — so every workspace package (`vendor/*`, `packages/*/*`, `apps/*`,
`native/landlock-run/packages/*`, 267 total) is symlinked into the root
`node_modules` during install. Without this, boot fails with dozens of
`Cannot find package '@deepseek-ai/dsh-client-…'` errors.

### Entry Path

The bin entry is `apps/cli/lib/bin.js` (`apps/cli/package.json` → `bin.dsh`),
NOT the deploy-root path `node_modules/@deepseek-ai/dsh/lib/bin.js` from the
upstream single-exe build — that file does not exist in a workspace build.

## Update Procedure

```bash
# 1. Version + source hash
nix store prefetch-file --unpack \
  https://github.com/deepseek-ai/deepseek-harness/archive/refs/tags/dsh-v<ver>.tar.gz --json
# 2. Edit manifest.json: version, srcHash, npmDepsHash = ""
nix build .#dsh   # fails with fixed-output mismatch → copy `got:` hash
nix build .#dsh   # green
# 3. Boot smoke test (see AGENTS.md)
```

The daily updater (`nix run .#update-custom-packages`) handles this
automatically: `upstream.tagPrefix` scans the releases list (`/releases/latest`
ignores prereleases — dsh releases are prereleases) and resets
`npmDepsHash` for the build-fail loop.

## Smoke Tests

```bash
OUT=$(nix build .#dsh --print-out-paths --no-link | tail -1)

# Composed config tree without booting:
DSH_HOME=$(mktemp -d) $OUT/bin/dsh --profile web --dump-config | head -30
# NOTE: --dump-config requires --profile; bare invocation errors.

# Live boot (stable server killed by timeout → exit 124, no import errors):
DSH_HOME=$(mktemp -d) timeout 40 $OUT/bin/dsh web --no-open
```

`--dump-config` imports nothing — it composes the tree only; it cannot catch
runtime import failures. The boot test is the real gate.

## Phase-2 Candidates (documented, not built)

1. **Landlock sandbox** — `landlock-run` (C11 launcher) binaries are not in
   the source tree (gitignored; npm-tarball-only). Without them dsh runs
   fail-closed without subprocess sandboxing (same as upstream macOS/Windows).
2. **Closure pruning** — 1.7 GB full workspace; a deploy-root closure exists
   upstream (`python/sdk-runtime` + `@yao-pkg/pkg` SEA route).
3. **Out-of-tree plugin profiles** — imperative `dsh plugin --profile <name>`
   remains available for disposable evaluation profiles; Nix-managed plugins
   use the scaffold (`docs/plugins.md`).
