# dsh Configuration Surfaces

How `my.features.dev.dsh` options map onto dsh's three configuration
documents, rendered by `lib/render.nix` into the user's `$DSH_HOME`
(default `~/.dsh`).

## The Three Surfaces

| Document | Written by | Semantics |
|---|---|---|
| `~/.dsh/settings.yaml` | `render.mkBaseSettings` + host `settings` + user `settings` (merged via `lib.recursiveUpdate`) | Per-namespace user settings, schema-validated, hot-reloaded |
| `~/.dsh/cordis.patch.yml` | `render.mkHomePatch` (insert rows) | Cordis tree composition on top of the profile's bundle layers |
| `~/.dsh/.credentials.yaml` | `render.mkCredentialsDoc` → sops template | Secret values, resolved per request |

All documents are emitted via `builtins.toJSON`. JSON is a strict subset of
YAML; dsh's YAML parser accepts it, comments are irrelevant because Nix owns
the document.

## Decision Rule: Settings Namespace vs. Patch Row

Before adding an option, check `docs/config-catalog.md` of the upstream repo
checkout (or the plugin's README):

- **The plugin registers a settings namespace** → the option renders into
  `settings.yaml` under that namespace. Hot-reloadable, schema-validated,
  survives UI writebacks of *other* namespaces. This is the default choice.
  Known namespaces wired today: `llm-deepseek`, `llm-pi-ai`,
  `agent-default-model`.
- **The capability has no settings namespace** (MCP server instances, persona
  composition, activating a plugin bundle) → an insert row in the patch
  layer: `{ id, name, config }`.
- **Overriding an existing bundle row** → a patch row with the same `id` and
  no `insert` key. Its `config` **replaces** the row's whole config.

Never insert a row whose id the dsh-base bundle already inserts
(`packages/bundle/base/cordis.patch.yml` in the upstream checkout lists all
of them: `agent`, `agent-default-model`, `llm-pi-ai`, `system-prompt`,
`tools`, `settings`, `credentials`, …).

## Option → Document Map

### Model adapters → `settings.yaml`

```yaml
# mkDeepseekSection — only fields deviating from upstream defaults
llm-deepseek:            # native adapter, route "deepseek-official"
  apiKeyEnv: DEEPSEEK_API_KEY      # rendered only when != default
  baseURL: …                       # null = $DEEPSEEK_BASE_URL, then public API
  thinking: enabled|disabled
  reasoningEffort: off|low|high|max
  maxTokens: …                     # default 256000
  contextWindow: …                 # default 1000000

# mkPiAiSection — dormant when empty (mounts no routes until a section exists)
llm-pi-ai:
  providers:
    <name>:                        # catalog routes need only apiKeyEnv
      apiKeyEnv: OPENROUTER_API_KEY
      api: openai-completions      # required for non-catalog routes
      baseURL: https://…           # required for non-catalog routes
      models:                      # replaces the installed catalog wholesale
        - id: meta/muse-spark-1.3-contributor
          contextWindow: 1048576
          maxTokens: 943718
          input: [text, image]     # hand-entered models are text-only otherwise
      defaultInput: [text, image]  # per-route fallback modalities
      compat: { … }                # wire-compatibility switches
      retryPolicy: { mode: normal, maxRetries: 3 }

# dsh-agent-default-model settings namespace — NOT a patch row
agent-default-model:
  provider: <route name>           # e.g. "openrouter-contributor"
  model: <provider-owned model id>
```

### Credentials → `.credentials.yaml` (version 1)

```yaml
version: 1
refs:                    # ← the only section we render
  DEEPSEEK_API_KEY: <sops value>
  OPENROUTER_API_KEY: <sops value>
```

- `refs` keys are POSIX env names; the credentials service resolves
  `apiKeyEnv` references against them (layering: inherited env wins, then
  refs, then `.env` fallbacks).
- `records` (`<scope>/<id>` keys) are owned by the Models page (sign-in
  data) and must not be rendered by Nix — a flat env name there fails the
  boot (`credential key "…" must be "<scope>/<id>"`).
- The sops template uses `mode = "0600"`: dsh refuses credential files with
  group/other bits set.
- The option type is `attrsOf (submodule { key })`. A plain `attrsOf str`
  forces `config.sops.placeholder` during the module merge while
  `sops.placeholder` is gated on `sops.templates != { }` → infinite
  recursion. Submodule checks are lazy; that is the proven pi pattern.

### MCP servers → patch rows

```yaml
- insert:
    - id: mcp-<name>
      name: '@deepseek-ai/dsh-mcp-client'
      config:
        serverName: <name>
        transport: stdio | streamable-http
        command: <store path or explicit command>   # stdio
        args: [ … ]                                 # stdio
        url: …                                      # streamable-http
        headers: { … }                              # streamable-http
```

Assertions enforce: stdio needs `(package + binName) | command`;
streamable-http needs `url`. Server packages join `home.packages` so their
store paths materialize (string context is stripped by `toJSON`).

### Profiles → `~/.dsh/profiles/<name>/`

`profiles.<name>.{bundles,patchReload,patches}` render to
`package.json` (`dsh.profile` manifest) and `cordis.patch.yml`. Unset
`bundles`/`patchReload` keep the upstream template (`initProfile` never
touches existing files — declarative management is safe).

## Host vs. User Layer

System-level options are host defaults; the user module merges
`lib.recursiveUpdate host user`. Escape hatches: `my.features.dev.dsh.settings`
(host) and `my.features.dev.dsh.settings` (user) render as raw
`settings.yaml` keys on top of the rendered namespaces.
