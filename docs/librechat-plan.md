# LibreChat — platform replacement plan

> **Status:** plan, not a specification. This file states an intention and the evidence behind it, so
> it is deleted when the migration lands ([`practices.md`](practices.md): documents describe the
> present; a migration diary belongs in the commit message). It exists until then because
> [`AGENTS.md`](../AGENTS.md) rule 1 - *prove the replacement before deleting the original* - needs
> the proof written down somewhere both sides can be read against.

## 1. Decision

Open WebUI on `cld-ops-01` is replaced by **LibreChat**. The replacement is motivated by three
measurements, not by preference:

| Claim | Evidence |
|---|---|
| Open WebUI is not an open-source licence | `LICENSE` clause 4 prohibits altering or removing the "Open WebUI" branding, as a *material condition*, except when "the total number of end users … does not exceed fifty (50) within any rolling thirty (30) day period" or an enterprise licence exists. |
| Real per-user isolation is a second, separate licence | [Terminals](https://github.com/open-webui/terminals), the only path to container-per-user isolation, is licensed under the *Open WebUI Enterprise License*: "may only be used in production, if you … hold a valid Open WebUI Enterprise License that includes rights to this Software for the correct number of user seats". |
| Built-in multi-user mode is not a security boundary | `open-terminal/SECURITY.md`: "It does not isolate users from each other, and it is not designed for production multi-user deployments." Reports asking for a boundary inside one shared container are closed as documented behaviour. |

LibreChat is MIT and brings its own isolation model: per-session sandboxes with NsJail or microVM
(libkrun) isolation, per-conversation approval policies for file writes and command execution.

Accepted cost: an additional database (MongoDB) and, for code execution, a separate service stack.
That cost is the subject of §7 and §8.

## 2. What the repository dictates

The form below is derived, not invented. Each row names the existing mechanism it follows.

| Existing mechanism | Consequence here |
|---|---|
| Recursive feature auto-discovery via `features/**/default.nix` (`lib/core/module-loader.nix`) | One directory, `features/services/librechat/`, is sufficient. Nothing registers it. |
| Feature dependencies via `features.requires [ "services.x" ] config` (`lib/features.nix`) | Databases are their own features, never inlined. |
| Everything is contract-projected (`my.contracts.provides.*`) | DNS name, Authentik application, firewall rule, portal tile and backup membership are never written by hand. |
| `architecture.md` §1.5: "The inventory decides … Writing an address twice means a derivation is missing." | The SearXNG URL is read from the SearXNG endpoint contract; no address and no second name is spelled out. |
| `identity.md`: "order across files is declared, never assumed" | Plugin composition carries an explicit `priority`; the merge order is a declaration. |
| `AGENTS.md` rule 1: prove the replacement before deleting the original | §9 keeps Open WebUI running until parity is measured. |
| `lib/endpoints.nix`: `endpointName svcName "web"` is `svcName` | The service id becomes `librechat`, so the Authentik application slug, the Prometheus `service` label and the portal tile id change. `ai.vyrx.de` does not: it follows from `subdomain = "ai"`, which stays. |

## 3. Placement and naming

```text
features/services/librechat/
├── default.nix                 # options, contracts, service wiring
├── lib/plugins.nix             # discovery; mirrors features/dev/pi/lib/plugins.nix
├── plugins/<name>/             # auto-discovered, one directory per plugin
│   ├── manifest.json
│   ├── module.nix
│   ├── skills/<skill>/SKILL.md
│   └── mcp/                    # optional wrapper for a stdio MCP server
└── skills/                     # skills shipped to every deployment
```

Option root: **`my.features.services.librechat`**.

Vocabulary is inherited verbatim from `features/services/open-webui/default.nix` -
`enable`, `port`, `subdomain`, `accessGroups`, `adminGroups`, `openMeshFirewall`, `sso.secretPath`,
`openAiEndpoints`. A new spelling for an existing concept would be a defect, not a liberty.

`subdomain` defaults to `"ai"`, so the user-facing name is unchanged across the migration. Only the
identifiers derived from the service name move (§2).

## 4. Option surface

```nix
my.features.services.librechat = {
  enable           = lib.mkEnableOption "LibreChat multi-user AI platform";
  port             = 3080;
  subdomain        = "ai";                       # → ai.vyrx.de, unchanged
  accessGroups     = [ "family" "infra-admins" ];
  adminGroups      = [ "infra-admins" ];
  openMeshFirewall = true;

  registration = { enable = false; allowedDomains = [ ]; };

  sso = {                                        # projected to OPENID_*
    enable       = true;
    clientId     = "librechat";
    secretPath   = "services/apps/librechat_oidc_secret";
    scope        = "openid email profile groups";
    rolesClaim   = "groups";
    adminRole    = "ADMIN";
    callbackPath = "/oauth/openid/callback";
  };

  database  = { enableLocal = true; uri = null; name = "librechat"; };
  search    = { enable = false; masterKeySecret = "services/apps/librechat_meili_master_key"; };

  webSearch = {                                  # built in, not an MCP server
    enable           = true;
    provider         = "searxng";                # searxng | serper | tavily | keenable | none
    scraper          = "none";                   # none | firecrawl | tavily
    reranker         = "none";
    allowedAddresses = [ ];                      # SSRF allowlist; extended from the SearXNG contract
    apiKeySecret     = null;
  };

  codeInterpreter = { enable = false; baseUrl = null; apiKeySecret = null; };   # §8

  openAiEndpoints = [                            # one list, projected into librechat.yaml
    {
      name         = "DeepSeek";
      baseUrl      = "https://api.deepseek.com/v1";
      apiKeySecret = "ai/deepseek_api_key";
      models.default = [ "deepseek-chat" ];
    }
  ];

  balance   = { enable = false; startBalance = 0; autoRefill = { enable = false; }; };

  skills     = { directory = ./skills; };
  mcpServers = { };                              # attrsOf submodule, §5
  interface  = { };                              # raw librechat.yaml `interface` block
  settings   = { };                              # escape hatch: raw librechat.yaml
  environment = { };                             # escape hatch: env, never a secret

  plugins = { extraDirs = [ ]; extraSettings = [ ]; };   # <name>.* added per plugin, §5
};
```

Two rules follow from §6 and are enforced in the module, not left to discipline:

- `settings` and `interface` may contain `${ENV_VAR}` references and nothing secret.
- Anything secret is declared once, as a SOPS path, and reaches the process only through
  `services.librechat.credentials`.

## 5. Plugin architecture

Pi solves the same problem with `plugins/<name>/{manifest.json,package.nix,module.nix}` discovered by
`lib/plugins.nix`, which exports `modules`, `derivations` and `packageDirs`. LibreChat's declarative
extension points are `librechat.yaml` (via `services.librechat.settings`), `DEPLOYMENT_SKILLS_DIR`
and - experimentally - `DEPLOYMENT_PLUGINS_DIR` (Agent Plugins). The plugin contract is the same
shape, targeting those points.

```nix
my.features.services.librechat.plugins.<name> = {
  enable      = true;
  priority    = 100;          # declared order; nothing is assumed
  settings    = { };          # raw librechat.yaml fragment, deep-merged
  mcpServers  = { };          # typed MCP entries
  skills      = [ ];          # skill directories
  packages    = [ ];          # stdio MCP servers, for the closure
  environment = { };
  secretPaths = [ ];          # SOPS paths, promoted to credentials
};
```

Composition in `default.nix`:

- **settings** - `lib.foldl' lib.recursiveUpdate` over plugins sorted by `priority`. Deterministic
  and declared, because a merge whose order is unknown produces a configuration nobody can predict.
- **skills** - LibreChat accepts one `DEPLOYMENT_SKILLS_DIR`, so several contributions are
  aggregated into a single store path (`pkgs.linkFarm`). `./skills` takes precedence, the same way
  a standalone deployment skill outranks a bundled one upstream.
- **mcpServers** - HTTP/SSE servers are written as URLs; stdio servers are referenced by absolute
  store path (`${package}/bin/${binName}`), and the package is added to
  `systemd.services.librechat.path` so the closure survives a `nix-collect-garbage`.
- **packages** go to the service's `path`, never into the environment.

When Agent Plugins leave their experimentation phase, the same discovered directory becomes the
Agent Plugins bundle; until then the stable surface is `settings` plus `DEPLOYMENT_SKILLS_DIR`.

## 6. Secrets

`services.librechat.settings` is rendered with `pkgs.formats.yaml` into the **world-readable Nix
store**. A token written there is a published token. Therefore:

- Secrets reach LibreChat through `services.librechat.credentials`, which the Nixpkgs module turns
  into `LoadCredential=<NAME>_FILE:<path>` and exports at runtime. This is strictly better than an
  `EnvironmentFile`: the value never appears in `/proc/<pid>/environ`.
- The paths come from `config.sops.secrets.<path>.path`. systemd reads them as root, so no owner or
  group has to be widened - which is the failure mode an `EnvironmentFile` would have required.
- Credentials LibreChat requires: `CREDS_KEY`, `CREDS_IV`, `JWT_SECRET`, `JWT_REFRESH_SECRET`;
  plus `OPENID_CLIENT_SECRET`, `MEILI_MASTER_KEY`, `MONGO_URI` when it carries a password, and one
  entry per provider key declared in `openAiEndpoints`.

## 7. Contracts

Projected exactly as `open-webui` projects them, with the service name changed:

```nix
my.contracts.provides.librechat = {
  endpoints.web = {
    port = cfg.port; protocol = "tcp"; scope = "public";
    auth = lib.optionalString cfg.sso.enable "oidc";
    accessGroups = cfg.accessGroups; adminGroups = cfg.adminGroups;
    subdomain = cfg.subdomain;
    directAccess = { enable = cfg.openMeshFirewall; protocol = "tcp"; interface = "wireguard"; };
    oidc = lib.optionalAttrs cfg.sso.enable {
      enable = true; clientId = cfg.sso.clientId; secretPath = cfg.sso.secretPath;
      redirectPaths = [ cfg.sso.callbackPath ];
      subMode = "hashed_user_id"; includeClaimsInIdToken = true;
    };
    dashboard = {
      show = true; displayName = "AI Assistant (LibreChat)";
      category = "AI & Agents"; icon = "message-circle";
      description = { de = "…"; en = "…"; };
    };
  };
  storage = { stateDirs = [ "/var/lib/librechat" ]; };
};
```

## 8. Open decisions

Four decisions change the code materially and are deliberately not pre-empted.

1. **MongoDB.** LibreChat requires it. Available in the pinned Nixpkgs: `mongodb` 7.0.43 and
   `mongodb-ce` 8.2.12 (both SSPL, unfree) and `ferretdb` 1.24.0. An MIT application on an SSPL
   database is a real tension given §1.
   - *(a)* a `features/services/mongodb/` feature declaring `my.contracts.provides.mongodb`, the way
     `postgresql` declares its own - consistent storage and backup handling; **preferred**.
   - *(b)* `services.librechat.enableLocalDB = true` - less code, no contract-declared lifecycle.
   - *(c)* FerretDB in front of the existing PostgreSQL - keeps the licence story clean, carries a
     compatibility risk that has to be measured before it is relied on.
2. **Actions versus MCP.** Actions are created in the UI and stored in MongoDB, so they are runtime
   state in an otherwise declarative repository. Choosing MCP instead means the integration work
   moves into this repository - the honest cost of the rule in §2.
3. **Meilisearch.** Required only for message search (§10).
4. **Code Interpreter.** A separate stack (§10), own feature, own phase.

## 9. Rollout

| Phase | Content | Proof |
|---|---|---|
| 0 | Settle §8 | - |
| 1 | `features/services/librechat/`, `lib/plugins.nix`, contracts, a **new** `librechat_oidc_secret` | `nix fmt`, `deadnix --fail`, `statix check`, `nix flake check` |
| 2 | Enable on `cld-ops-01` **alongside** Open WebUI; reach it by port over the mesh, not by `ai.vyrx.de` | service active, OIDC login succeeds |
| 3 | Parity measurement against the list below | measured, written down |
| 4 | Cut `ai.vyrx.de` over; accept the identifier moves of §2 | login, chat, a backup restore probe |
| 5 | Delete `features/services/open-webui/`, tombstone the SOPS entry, follow the `wmClass` reference in `user/philipp/home.nix` | `nix flake check` and the audit |

Parity checklist for phase 3, each item a measurement rather than an impression:

- OIDC login, and a group that is *not* in `accessGroups` is refused.
- `adminGroups` membership yields the admin role; a plain member does not.
- Chat against every endpoint in `openAiEndpoints`.
- Web search answers through the fleet's SearXNG, and a private address outside
  `allowedAddresses` is refused.
- `/var/lib/librechat` appears in the backup contract's path list.
- The portal tile renders and links to the right name.

## 10. Deferred

**Message search** (Meilisearch) and **code execution** (the Code Interpreter API) are optional
capabilities with independent costs. Each is a separate feature, a separate decision (§8) and
neither is required for LibreChat to replace Open WebUI: chat, identity projection, model endpoints
and web search are complete without them.
