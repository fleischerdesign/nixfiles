# dsh Plugins

Two ways to extend dsh declaratively: in-tree bundles (shipped with the dsh
installation) and out-of-tree community plugins (packaged under
`features/dev/dsh/plugins/`).

## Discovery Mechanics

`lib/plugins.nix` scans `plugins/*/package.nix` at eval time:

- Each directory becomes a derivation (`pluginsLib.derivations`).
- Each directory gets a `my.features.dev.dsh.plugins.<name>.enable` switch
  (default `true`; the option map is sparse, missing keys mean enabled —
  `cfg.plugins.<name>.enable or true`).
- Active plugin derivations are injected into the user's home and activated
  via generated bundle rows in the home patch layer.
- `features/**/manifest.json` is scanned by
  `lib/updaters/update-custom-packages.sh` — plugin version pins update
  automatically with the daily cron.

Adding a plugin = one new directory. No registration anywhere.

## Adding an Out-of-Tree Plugin (walkthrough)

Example: `features/dev/dsh/plugins/dsh-cost-meter/`.

### 1. Inspect the plugin

Clone the upstream repo. Check:

- `package.json` → `dsh.bundle.patch` present (it is a proper bundle)?
- Prebuilt `lib/` committed, or does it need a build step?
- Native modules / lifecycle scripts? (avoid or handle in `package.nix`)
- Third-party runtime deps → these must ship **inside** the plugin's
  `node_modules` (see step 3).
- `dsh.compatibility` → does it support the pinned dsh version?
- License, activity, maintainer reputation (Discovery sources:
  github.com/topics/dsh, the `awesome-dsh-plugin` list, dshx.io,
  dshplugins.com — review is a quality signal, never a security warranty;
  Nix pinning is our supply-chain control).

### 2. Pin it: `manifest.json`

```json
{
  "name": "dsh-cost-meter",
  "version": "1.7.12",
  "srcHash": "sha256-…",          // nix store prefetch-file --unpack <tarball> --json
  "npmDepsHash": "sha256-…",      // build-fail loop (empty string first)
  "upstream": {
    "type": "github-source",
    "owner": "Han-1413141",
    "repo": "dsh-cost-meter",
    "rev": "<commit>"              // or tagPrefix + version for tag releases
  },
  "bundle": "dsh-cost-meter"       // npm package name the bundle row references
}
```

### 3. Derivation: `package.nix`

Model: `plugins/dsh-cost-meter/package.nix`. Key points:

- `fetchPnpmDeps` with `pnpm = pnpm_11` and `fetcherVersion = 4` (mandatory
  for pnpm ≥ 11), wired via `pnpmConfigHook`.
- `dontBuild = true` when upstream ships `lib/` committed.
- **Install the plugin's own `node_modules` alongside `lib/`** — bare-name
  imports (`zod`, …) must resolve inside the plugin directory. Pinned
  `@deepseek-ai/*` helper copies ride along, exactly like the imperative
  `dsh plugin add` layout.
- `passthru.dshPluginName = manifest.bundle or manifest.name;`
- Install layout: `$out/lib/node_modules/<dshPluginName>/{lib,node_modules,package.json,cordis.patch.yml}`.
- npmDepsHash discovery: set `"npmDepsHash": ""`, build, copy the `got:`
  hash from the fixed-output mismatch, rebuild.

### 4. Verify

```bash
nix build --impure --expr \
  'let pkgs = import <nixpkgs> {}; in
   pkgs.callPackage ./features/dev/dsh/plugins/<name>/package.nix {}'
# Boot test with the plugin linked at ~/.dsh/node_modules (read-only is fine):
DSH_HOME=$(mktemp -d) … $OUT/bin/dsh web --no-open
# Gate: zero "failed to import" lines; plugin banner (e.g. [dsh-cost-meter]) present.
```

## Injection Point (do not change)

Active plugins land at **`~/.dsh/node_modules/<name>`** (HM `home.file`
symlinks into the plugin derivation). Rationale:

- Bundle names in patch layers resolve via Node's parent-walk:
  `profiles/web/node_modules` → `profiles/node_modules` → `.dsh/node_modules`.
- `~/.dsh/profiles/node_modules/` is **written by the launcher itself**
  (module-fallback healing: it creates `@deepseek-ai/…` links there). An
  HM-managed read-only directory there crashes the boot with `EACCES`.
- `.dsh/node_modules` is never touched by the launcher; read-only store
  symlinks are safe (verified under simulated HM conditions).

## Activating In-Tree Bundles (no packaging)

The dsh installation ships ~45 `@deepseek-ai/dsh-*` plugins; dsh-base
activates a subset. Others (e.g. `@deepseek-ai/dsh-plan-mode`) activate via
profile patches — new rows insert, existing rows override by id:

```nix
my.features.dev.dsh.profiles.web.patches = [
  {
    insert = [
      { id = "plan-mode"; name = "@deepseek-ai/dsh-plan-mode"; config.section = "…"; }
      { id = "schedule"; name = "@deepseek-ai/dsh-schedule"; }
    ];
  }
  # { id = "hmr"; disabled = false; }   # override example (replaces config!)
];
```

Deactivating a plugin: `my.features.dev.dsh.plugins.<name>.enable = false;`
(skips build, injection, and bundle row).

## Community Plugin Sources

- github.com/topics/dsh (~6.3k repos) and the `awesome-dsh-plugin` curated
  list (~3.2k entries, 23 categories, source-verified)
- dshx.io / dshplugins.com registries (indexed metadata)
- `dsh-find-plugin` (in-agent search) — not packaged; Nix is our registry
