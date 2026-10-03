# Personal AI gateways

## Ownership and placement

`inventory/identity.nix` declares the `ai-users` provisioning group; `inventory/site.nix`
declares the default gateway host.
The directory contract projects this exact membership into Authentik. The OpenClaw feature
creates one gateway per member on the configured gateway host when the feature is enabled.
Ordinary Authentik role membership remains interface-owned; this group is deliberately
repository-owned because it determines infrastructure existence.

Profiles under `user/<username>/openclaw.nix` are optional NixOS modules, discovered by their
distinctive file name. They configure `my.features.services.openclaw.users.<username>`.
A group member without a profile receives the generic gateway defaults, not another person's
provider keys, Google tokens, GitHub access, vault or administration grants.

Each gateway has a separate Unix account (`openclaw-<username>`), configuration, state
directory and listener. Ports are stable functions of usernames; a collision fails evaluation
and requires a profile override. Gateway placement can be overridden per person. Hosts contain
feature activation, not personal OpenClaw configuration.

The plugin catalogue is `features/services/openclaw/plugins/`: one folder per plugin, discovered by its
`plugin.nix` marker through the shared `lib/discovery.nix`. The folder name **is** the plugin
identifier, so a plugin does not restate its name; nix-openclaw derives the package attribute and the
generated lock file from that same name. `plugins.nix` is the feature-local loader that validates each
record and rejects an unknown field, so a plugin that needs more than `npm` and `contribution` must
extend the contract there. A profile names identifiers, never package paths. `deepseek` and
`tokenjuice` are continued from the OpenClaw feature this repository ran before the current one;
`searxng`, `diffs`, `lobster` and the `codex` agent runtime arrive with it.

Plugins are **bundled into the gateway closure**, not named through `plugins.load.paths`. OpenClaw
resolves trust-gated runtime surfaces (`openBlobStore`, `openKeyedStore`, channel ingress queues) only
for a plugin whose origin is `bundled` or whose install record is `trusted-official`; a load-path
root is neither and is recorded as `record-missing`. nix-openclaw's own supported `runtimePlugins`
path renders the same load path, so this is a property of Nix-declared plugins. A plugin that touches
such a surface fails at registration from a load path - `diffs` calls `openBlobStore` and did exactly
that. `build.nix` therefore copies each catalogue plugin into the gateway's own `extensions/<id>` and
`dist/extensions/<id>`, the same physical-containment mechanism nix-openclaw uses for its bundled
ACPX runtime. The plugins are built without the OpenClaw peer link so the gateway does not depend on
itself; the host SDK resolves from the containing gateway.

The PC role requests a graphical-session node for its primary user. A node is generated only
when that person is in the provisioning group. Gateway node admission is derived from these
placements, not a second list of devices.

## Configuration and state

`release.nix` declares the OpenClaw release this fleet runs; `build.nix` resolves it, and the plugin
catalogue under `plugins/` against the pinned `nix-openclaw` input. The two must agree: a version
change without a matching packaging input fails evaluation with both values named. A profile names
plugin **identifiers** (`enabledPlugins`); the catalogue decides the package, so no profile carries a
store path and an identifier the catalogue does not declare fails evaluation.

Nix generates immutable JSON, packages plugins, adds declarative skill directories and supplies
executables through runtime wrappers. Updates and persisted plugin-registry overrides are disabled.
Native plugin settings still decide which packaged plugins are enabled. There is no configuration
reconciler. Native `mcp.servers` remain available for connectors; their secrets come from the
credential files, never from the generated JSON.

Listener ports are derived, not hand-numbered. `ports.nix` is the single definition of every offset:
OpenClaw builds the Browser Control port from the gateway port (`+2`) and allocates its managed Chrome
CDP ports from `+11`; MCP Apps therefore defaults to `+1` and the publishing router to `+2048`. The
feature asserts that gateway, MCP Apps, Browser Control, the CDP band and the publishing router do not
overlap on a host, and `checks/openclaw-feature` reads the same offsets rather than restating them.
Hand-numbered internal ports are what produced the original collision: MCP Apps at the Browser Control
port.

The feature check measures the consumer-visible fact, not just the build's own writes:
`checks/openclaw-plugins-loaded.py` runs the built gateway binary and asserts that every catalogue
plugin is discovered with `origin=bundled`, `status=loaded` and `trust=bundled`. Reading the extension
files back would only prove that Nix copied them.

### Deliberate audit findings

`openclaw security audit` over the generated configuration reports a fixed, intended set. None is a
defect; each is a consequence of the architecture, and a change to this list should be deliberate:

| Finding | Why it is intended |
|---|---|
| `gateway.trusted_proxy_auth` (critical) | The central ingress is the only browser authentication path. The proxy address and the single accepted owner are inventory-derived, and only WireGuard sources reach the port. |
| `gateway.trusted_proxy_device_auto_approve` | The proxy is the exclusive ingress and restricts to `allowUsers`; auto-approval is what lets the owner's browser pair without a second manual step. |
| `tools.exec.security_full_configured` | The owner's assistants run on the owner's behalf; local and fleet access are separately declared and separately credentialed. |
| `browser.ssrfPolicy.dangerouslyAllowPrivateNetwork` | The browser must reach contract-declared internal services such as SearXNG. The mesh and the firewall remain the network boundary. |
| `mcp.apps.enabled` | MCP Apps is a declared, separately published origin behind the same ingress. |
| `fs.config.symlink` | The generated configuration is immutable by construction; the store path is the point. |
| `fs.config.perms_world_readable` | The store copy is world-readable, as every `/nix/store` path is. The file holds secret *references* (environment variable names), never values; the referenced secret files are mode `0400`. |

The audit's `secretDiagnostics` about `gateway.auth.password` are expected: the command path does not
receive the SOPS environment, so it reports the reference as unresolved. The running unit resolves it.

OpenClaw owns mutable state below `/var/lib/openclaw/instances/<username>`: conversations,
memory, automation, workspaces, devices and native credentials. Native nodes keep their device
identity and managed worktrees below `/var/lib/openclaw-nodes/<username>/<gateway>/<instance>`.
Both are service state, not user data: every level is declared with its runtime owner, so the chain
is correct on first boot and systemd-tmpfiles never has to create a root-owned directory below a
user-owned one. Runtime wrappers select the appropriate state and configuration; they read private
credential files literally, never as shell code. SOPS supplies provider and integration secrets.
Secret values are not written into generated JSON or the Nix store.

## Authentication boundaries

The browser publication is ingress-only. DNS on every plane points it at the central ingress;
no second local Caddy route bypasses authentication. Caddy removes incoming identity and scope
headers before Authentik authentication. The gateway trusts only the inventory-derived ingress
proxy address and accepts only its owner's username. Its browser audience is the owner's
generated identity group, not the whole `ai-users` group.

The publication exempts `/j/*` and `/__openclaw__/worker` from Authentik forward-auth:
OpenClaw validates the single-use join codes and short-lived worker credentials itself.
Caddy still strips client-supplied identity and scope headers on these routes. The
Control UI has no authentication bypass. Native WebSocket upgrades without an `Origin`
header bypass forward-auth as well, but receive no trusted identity headers. OpenClaw verifies
their signed device identity and bootstrap or device token in its native handshake. Requests
with a browser `Origin` still require Authentik. Worker credentials are distinct from node tokens.

Native nodes connect directly to the gateway over WireGuard. Firewall admission names only
their inventory hosts. Admission is not authentication: nodes require OpenClaw's own pairing
and device credentials. There is no SSH tunnel or browser machine-auth bypass. The private
WebSocket transport explicitly relies on WireGuard for encryption.

Nodes must not receive a shared Gateway password: it suppresses selection of the stored device
token in the upstream client. Each device retains its own private identity and role-scoped token
in mutable state. Enrollment and capability approvals apply equally to declarative nodes and
devices outside the inventory, including mobile apps. Public native connections use the TLS
publication; direct WireGuard connections remain limited to the declared endpoint sources.

The native gateway uses its all-interface listener so the same process is reachable on loopback
for local administration and on WireGuard for ingress and nodes. Only the declared WireGuard
sources are admitted externally; this is not an unfiltered public listener. The trusted-proxy
mode's separate local-direct password path is available to Philipp's gateway wrapper. It does
not accept that password as a remote browser or node bypass.

For enrollment, run the gateway wrapper as its Unix account to mint a native setup code with
`qr --url ws://<gateway-mesh-address>:<port> --json`. Keep the code private. On the personal
device, stop the generated user unit and run its node wrapper with `node run --pair <setup-code>`.
Review the gateway's `nodes pending` output and approve the intended capability surface with
`nodes approve <requestId>`; successful device pairing alone is not capability approval. Stop
the enrollment process and start the user unit again. It reconnects using persistent native
device credentials, not the bootstrap code. Use the wrappers rather than bare OpenClaw so state
paths and configuration stay correct. These commands use the host's fish shell; do not use
POSIX inline environment assignments there.

For mobile apps and devices outside the inventory, mint the setup code with
`qr --url wss://<personal-gateway-domain> --json` instead. Scan or paste that native setup
code in the app; it is not a `/j/` join URL. The public TLS endpoint permits native
WebSockets without an `Origin`, while the ordinary browser still authenticates through
Authentik. Review requested roles, scopes and capabilities before approving the device.

Graphical nodes run as the desktop user, not root. Chromium is available to the native browser
proxy. This does not imply general Wayland computer-control compatibility: `wtype` provides
an executable, not a verified OpenClaw Niri computer-control implementation.

The PC role enables the bundled `linux-node` plugin's camera and notification surfaces and
provides FFmpeg and `notify-send` in the node wrapper's PATH. The gateway loads the same plugin
for its node-invoke policies and explicitly allows `camera.snap` and `camera.clip`. This consent
applies to eligible paired nodes, not only one inventory host. Device admission, approved command
surface, local capability enablement and OS access remain independent requirements. Camera access
uses the desktop user's existing session permissions; no permanent `video` group grant is added.
Location remains disabled without a qualified GeoClue provider. General desktop control is not
enabled for Niri/Wayland. `checks/openclaw-feature.nix` exercises the pinned Linux plugin's actual
advertisement gates for both PC host classes without capturing media.

The personal agent's exec target is `auto`: without a sandbox, unspecified calls stay on the
gateway, while an explicit paired-node target is permitted. Fixing the target to `gateway`
would reject node overrides and exclude node-hosted skills. Node command approval and local
exec policy still apply; `auto` does not grant device admission or additional OS permissions.

Session hosting is enabled on PC nodes. A missing worker bundle is an observation, not proof of
broken provisioning: the gateway transfers and verifies its sealed artifact when a session first
needs that build. MCP and local-inference capability labels likewise do not prove that servers or
models are configured; qualification must discover and invoke an actual published tool or model.

Consumer-level qualification on `hom-wrk-01` (2026-10-03): `nodes camera list` identified the
UGREEN V4L2 camera; `nodes invoke camera.snap` with a nonexistent exact device id reached the
node and failed without capture. An authorized single-frame `camera.snap` returned a valid
640 × 360 JPEG without audio; validation retained no additional image file. `nodes notify`
returned success. `browser.proxy` start/status/stop
proved Chromium and CDP readiness; `terminal.upload` produced byte-identical content on the PC.
`sessions.create` with an empty managed worktree followed by `sessions.dispatch` reached active
device placement; `sessions.reclaim` and archive released the test session. After a node-service
restart, `nodes status` showed approved camera/notification commands and the installed worker
bundle. These measurements do not qualify video/audio capture, a hosted model turn, or the notebook.

## Memory

The native backend is the active slot (`plugins.slots.memory = "memory-core"`): Markdown files plus one
SQLite index, hybrid BM25 and vector search, deterministic trigger recall, provenance per indexed
chunk, and a gated dreaming consolidation pass. No second memory store is added — LanceDB would
duplicate the same capabilities without the provenance boundary, and Honcho is an external service.

Two recall paths are enabled, both scoped to `main`:

- `memory.search.rememberAcrossConversations` lets the personal agent recall relevant context from its
  own other private conversations. It implies session transcript indexing, so the global
  `memory.search.sources` stays unset and OpenClaw derives it. That derivation is per-agent; setting
   `sources` globally would override that agent-local derivation.
- The `active-memory` plugin runs bounded deep recall in `escalate` mode: only for recall intent when
  the deterministic lane found no strong trusted hit, only for direct conversations, with a 15 s
  budget. It must be in `plugins.allow`; a configured-but-not-allowed plugin is only a validator
  warning, not a working feature.

Dreaming is named explicitly (`memory-core.config.dreaming.enabled`). Its scheduled sweep reconciles
from the default agent's heartbeat, which runs with `target = "none"` here, so the pass fires while
the notification stays internal.

**Data flow.** `memory.search.provider = "openai"` sends every indexed text to OpenAI to be embedded:
the Obsidian vault (`extraPaths`) and, with cross-conversation recall on, conversation transcripts.
This is a deliberate choice, not a side effect. A local provider (`ollama` or `llama.cpp`) removes the
egress but requires a full reindex (`openclaw memory index --force --agent main`), because changing
the embedding identity invalidates the existing vector index.

Provenance is the security boundary, not search: content classified `untrusted` — web fetches, tool
output, non-owner participants — can never be promoted into `MEMORY.md`. That gate is structural, so
the admission policy (`memoryPolicy.excludeSessions`) is deliberately left unset until a concrete
source needs excluding.

**What is verified, and what is not.** The generated configuration is measured: the memory slot, the
provider, the absence of a global `sources`, the per-agent setting, the active-memory scope and its
allowlist entry. That proves the configuration, not that recall works. Whether Active Memory returns a
useful hit, whether dreaming actually sweeps, and whether cross-conversation recall surfaces the
right context are only observable in a running gateway with `/trace on` and
`openclaw memory status --deep` — and have not been measured here.

## Personal integrations

Philipp's profile declares provider plugins, the personal agent Moebius, writable Obsidian access,
Google Workspace, GitHub tooling and explicit local administration. These are profile choices,
not capabilities implicitly granted to every group member. The plugin identifiers are the
repository's reviewed allowlist (`plugins.nix`); the previous feature's `deepseek` and
`tokenjuice` are continued, `searxng` implements the web-search provider, `diffs` and `lobster`
contribute tools, and `codex` is the runtime the GPT-5.4 fallback routes through. `device-pair`
is bundled with OpenClaw and enabled so native nodes can be paired.

Moebius is the only configured agent. Its stable internal id is `main`, including the default
system-agent selection and memory-plugin scope. Research, coding and operations are capabilities
of this agent, not separate permanent personas. Temporary subagents may target `main`; they return
results to their parent without cross-agent messaging. Session visibility is `agent` and
agent-to-agent messaging is disabled. Heartbeats use
`target = "none"`: there is no messenger channel, so a heartbeat surfaces in the session rather than
claiming a delivered notification. Recurring checks belong in automation jobs with explicit targets.

The packaged `personal-platform` skill describes platform access and configuration ownership,
not persona or delegation strategy. Workspace instructions (`AGENTS.md`, `SOUL.md`, `USER.md`,
`IDENTITY.md`) and workspace skills remain native mutable state. A packaged skill is guidance,
not a permission boundary; workspace skills can take precedence over extra-directory skills
with the same name.

The Google integration imports a SOPS OAuth client into a private `gog` configuration directory
and initializes a private file-keyring password. OAuth consent must be completed interactively
as the gateway account using its `openclaw-<username>-exec` wrapper. OAuth tokens and keyring
state are mutable, private and backed up. Browser/internal-service login sessions likewise
require enrollment; an installed browser does not create authenticated sessions.

`obsidianBridge` names an already enabled LiveSync bridge. The integration assigns its vault to the
gateway account and leaves the vault a **replica**: the bridge is bidirectional, CouchDB is the source
of truth, and the vault lives inside the gateway's state directory, which the backup contract excludes.
Restic excludes are global, so a vault inside that tree could not be backed up even if it were listed;
declaring it regenerable is the classification that matches reality. Durability comes from CouchDB,
which the edge host already backs up through its broad `/var/lib` path.

Fleet SSH requires an explicit `fleet.privateKeyFile` and `fleet.publicKey` pair. The feature
projects only the declared target hosts' root keys and source admission. SSH uses strict host-key
checking and the system known-hosts file. Local root administration and fleet SSH are distinct:
without the pair the feature warns and does not create working fleet credentials. The operator's
deployment key is not implicitly borrowed.

## Publishing

An enabled publishing integration declares a separate public wildcard publication beneath
`pub.<username>.ai.<domain>`. This is intentionally public, not an Authentik-protected control UI.
A dedicated Caddy router, running as the gateway user, maps a single validated application label
to `/run/openclaw-publishing-<username>/sockets/<app>.sock`. Unknown hosts receive 404; missing
application sockets are upstream failures. The ingress obtains the wildcard certificate through
DNS-01. The socket directory is private and ephemeral, so persistent applications must recreate
their sockets when their processes restart.

The publishing skill requires explicit operator permission before exposure. Applications must
provide their own access control if they are not meant to be public. Publishing an application
must never expose gateway state, credentials or management endpoints.

## Backup and recovery

The backup contract invokes `openclaw backup create --verify` as the gateway account before
Restic runs. The hook requires exactly one archive and atomically replaces the previous verified
archive only after success. Restic includes that archive; the vault is a regenerable replica of
CouchDB and is excluded. Private provider credentials remain in SOPS. Native SQLite snapshots are
consistent, but the whole collection of assets is not an atomic cross-service transaction.

Before recovery, stop the gateway and the bridge, retain the current state, inspect and verify the
selected native archive, and let the bridge repopulate the vault from CouchDB. Restore mutable OpenClaw
state using the pinned release's native backup format while keeping configuration Nix-owned. A Nix
generation rollback alone does not reverse database migrations, device enrollment or OAuth state.
Rotate exposed credentials and revoke lost devices rather than trusting a restored credential merely
because the archive verifies.

`backup restore <archive> --target <fresh-directory>` verifies and extracts into staging, never
in place. Use its `manifest.json` to identify each state and workspace asset before offline
activation. Restore declaratively packaged plugins by rebuilding Nix, not by running a native
plugin installer against the immutable configuration.
