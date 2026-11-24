# Operations

> **Audience:** operators and autonomous agents. How to deploy, reach a host, verify a change, recover
> one you locked yourself out of, and keep the fleet updated. This document states the present; a
> resolved incident belongs in the commit that resolved it.

## 1. Golden rules

1. **Never remove your out-of-band path.** Before any network change, keep at least one working path
   that does not depend on what you change: public-address SSH on the cloud hosts, the WireGuard mesh, a
   wired client with a static address in the affected subnet, or a physical console.
2. **Exactly one DHCP server per segment.** Never run the box DHCP and Kea on the same subnet at once.
3. **Never point DNS at a host that is not serving DNS yet.** The box may resolve through `10.10.10.10`
   only once the resolver answers.
4. **The box is the WAN modem.** The reconciler manages its DNS, DHCP toggle and port forwards only -
   never its LAN address, subnet or Wi-Fi.
5. **Backups and a rollback path first.** Record the current generation before you touch anything.
6. **Preview before activating**, and keep the working tree clean (`nod plan`, `--dry-run`).
7. **Home network changes are maintenance windows.** Do them on site or with guaranteed wired access.

## 2. Reaching a host

| Situation | Use |
|---|---|
| cloud host, any time | public address: `root@173.249.22.211`, `root@37.114.55.91` - the lifeline that survives a broken mesh, a bad route or a lockout |
| everything else | the mesh: `root@10.10.100.x` |

Hosts, zones and addresses are in [architecture.md](architecture.md) §2 and §3. Reach the fleet with
`~/.ssh/nixfiles-deploy-key`. `~/.ssh/deploy-key` is the node tunnel secret and must never address a
fleet host.

## 3. Deploying

```bash
nod plan <host>                                                 # preview
nod switch <host>                                               # fleet deploy: build, transfer, activate
nixos-rebuild switch --flake .#<host> --target-host root@<addr> # one host
nod rollback <host>                                             # rollback
```

`nod` reads `#nixosConfigurations` and the `nodTargets` projection: every deploy target - the five
hosts, the agentless router, access point and Cloudflare reconciler, and each ESPHome device - maps to
the `targetHost` it dials, which for a host is its WireGuard address. An `output-surfaces` check forces
the projection and requires every target to name an address, so a broken deploy surface fails the build
instead of a rollout. There is deliberately no `deploy` output.

Deployment is not coupled to health probes: a rebuild must be fast and atomic, and the monitoring stack
alerts independently of who deployed what.

### Automatic reconciliation

`cld-ops-01` runs `nod daemon` (`my.features.system.nod-sync`). It tracks `main`: a `git ls-remote`
gate every 60 s, a fast-forward-only integration, one drift comparison per host, and a canary rollout
with automatic rollback. Hosts whose closure already matches are skipped, and the host that runs the
daemon is deployed last.

Pushing to `main` is therefore the deploy button; the control is the review before the merge, not the
daemon (ADR-028 in the `nod` repository). Every host is in scope: a machine that is off or off the mesh
is reported as unreachable and skipped, and the next cycle picks it up when it is back.

State and the checkout live in `/var/lib/nod`; `systemctl status nod-sync` and
`journalctl -u nod-sync` show the loop. A refused cycle - dirty checkout, non-fast-forward,
downgrade - touches nothing and is visible in the journal.

`nod switch cloudflare --dry-run` previews orchestration, not DNS changes; preview the actual diff with
`nix run .#sync-cloudflare -- --dry-run --prune` and read it in full before applying.
`checks/cloudflare.nix` exercises the action contract and reconciliation against isolated fixtures,
including idempotency and protection of foreign and ACME records. `inventory/dns.nix` declares the
external-provider DNS requirements (SMTP2GO sender-domain return-path, DKIM and tracking CNAMEs)
separately from the reconciler; reconcile them and confirm their public answers before requesting
sender-domain verification. These records do not configure SMTP credentials or replace existing MX, SPF
and DMARC records.

**Pre-flight, every session**

- `git status` clean, changes committed;
- `nix flake check` passes;
- the required SOPS secrets are present and decryptable on the target;
- a backup exists and the current generation is recorded (`readlink -f /run/current-system`);
- out-of-band access is confirmed; for a network change, a second device with a static address in the
  affected subnet is online.

**Order.** Servers first (they carry the contracts, outposts and relay hubs), the home LAN core before
the clients that depend on its DHCP and DNS, clients after, embedded network devices last - they change
connectivity and need the servers healthy for a rollback.

## 4. Onboarding a roaming client

A device that cannot run NixOS joins the mesh as a node: one `my.topology.hosts` entry with
`hostType = "client"`, an overlay address and its WireGuard public key. Its private key lives in SOPS at
`infra/wireguard/<name>_private_key`, like every host. The host that declares
`my.features.system.networking.wireguard.clientConfigs = [ "<name>" ]` renders the wg-quick file at
activation, with the key injected by sops-nix (Nix cannot read a SOPS value at build time). Scan it once:

```bash
sudo qrencode -t ansiutf8 -r /run/secrets/rendered/wg-<name>.conf
```

Use `-r`, not a shell redirect: the file is root-only, and `< file` would be opened by the operator shell
before `qrencode` runs.

The profile carries the mesh resolvers as `DNS =`, which is what makes the VPN network able to resolve a
name at all. It is the bootstrap, not the setting: the resolver the device actually uses is still a
choice of its own (Android: *Settings - Network - Private DNS*, hostname `dns.vyrx.de`), and both are
needed - private DNS is global and covers the networks the tunnel is not up on. Verify on the device: a
blocked name must answer `127.0.0.1`, the cloud door must show the client on port 853, and the VPN network
must carry a DNS address rather than an empty list.

An Android client bound to a split-tunnel VPN network gets no `INTERNET` capability, so an app that
requires it (Google push transport) will not use that network - notifications stall until the tunnel is
off. The answer is a per-device declaration: `excludedApplications = [ "com.google.android.gms" ]` on the
host entry, rendered as `ExcludedApplications` in `[Interface]`. The key exists only in the Android client
(`com.wireguard.config.Interface`), so iOS must not set it. Revocation is the inverse, plus the key
rotation in [identity.md](identity.md) §2.

## 5. Verification

```bash
ssh root@<addr>  'systemctl --failed; readlink -f /run/current-system'
ssh root@10.10.10.10 'dig +short @127.0.0.1 vyrx.de; journalctl -u kea-dhcp4-server -n 20'
ssh root@173.249.22.211 'wg show'
nix run .#network-audit                              # every host, on the path it actually uses
nix run .#exposure-audit -- --strict                 # every listening socket, decision or question
```

A deploy is verified when `systemctl --failed` is empty on the host and the activation returned `exit 0`.

## 6. Emergency recovery

Stop as soon as one path works.

1. **Key-based user login**, no password involved: `ssh -i ~/.ssh/id_rsa philipp@173.249.22.211`,
   `…@37.114.55.91`, `…@10.10.10.10`. On the home server this is root already:
   `ssh -i ~/.ssh/id_rsa root@10.10.10.10`.
2. **The mesh:** `ssh root@10.10.100.x`, if peers handshake.
3. **Wired LAN** from a static-address client: `ssh root@10.10.10.10`, box UI `http://10.10.10.1`, AP UI
   `http://10.10.10.20`.
4. **Physical console** for home hardware.

**Which key root trusts.** `hom-srv-01`, `cld-ops-01` and `hom-wrk-01` trust the operator key and the
fleet deploy key (`~/.ssh/nixfiles-deploy-key`, authorised through
`my.features.system.networking.ssh.deployKeys`). The operator key stays authorised everywhere as the
fallback, and `~/.ssh/config` sets no `IdentitiesOnly`, so a mistake here cannot lock the fleet out.

**A bad configuration.** `ssh root@<reachable> 'nixos-rebuild --rollback switch'`, or reboot and pick the
previous generation in the bootloader.

**A lost account password.** `root` is not an option: `PermitRootLogin = prohibit-password` and no root
password is declared. Servers set `users.mutableUsers = false`, so the declared hash is the source of
truth and a hand-set password is overwritten at the next activation.

- *The old password, without touching the host.* Check candidates against a hash from history:
  `git show <rev>^:secrets/secrets.yaml > /tmp/old.yaml`, extract the salt, then
  `openssl passwd -6 -salt "$salt" '<candidate>'` and compare.
- *GRUB over the provider console* (fastest; GRUB has no password): reboot, at the menu press `e`, append
  `init=/bin/sh` to the `linux` line, Ctrl-X, then `mount -o remount,rw /`, `passwd <user>`, `reboot -f`.
- *The provider rescue system:* mount the root filesystem, bind `dev proc sys`, `chroot`, `passwd`.

After a manual change, **fix the declaration too**: with `mutableUsers = false` the next activation writes
the declared hash back, so the password in SOPS is the source of truth and the host is a copy of it.

**A lost network service.** DHCP gone: configure a client statically, re-enable the box DHCP, stop Kea.
DNS gone: point the client at `1.1.1.1`, re-point the box DNS, fix the resolver. Box unreachable: its
default LAN `10.10.10.1` remains the anchor and it is still the modem. Complete loss at home: the box is
still the modem, so recover through it rather than around it.

## 7. Known hazards

Standing conditions that will bite an operator who does not know them.

| Hazard | Why it matters |
|---|---|
| The box DHCP is **off** in the desired state | enabling Kea before reconciling the box gives two DHCP servers on one segment, or none |
| Applying the access-point reconciler unifies the SSIDs to the fleet name on both bands and needs the AP at its current address | it changes the WLAN for everyone, including microcontrollers that store the SSID |
| The remote forward-auth outpost is reached at an overlay address (`10.10.100.1:9055`) | logins on LAN hosts break while the mesh is down |
| The resolver blocklist refresh must not claim the resolver directories | declaring `RuntimeDirectory`/`StateDirectory` for it makes systemd re-own `/run/knot-resolver` and `/var/lib/knot-resolver` as root and kills both resolvers; the refresh writes one file and reloads through systemd |
| The box IPv6 settings are set by hand | a firmware update or reset brings back router advertisements and DHCPv6, and with them a second resolver that answers our names with the public address - silently. Check with `rdisc6 -1 <iface>`: nobody must answer |
| Nothing forces a device to use our resolver | DHCP offers only ours and the box no longer announces itself, but the segment is flat, so a hand-configured device can still bypass it. The remedy is a second segment, not a firewall rule |
| `nod switch` writes the boot entry but advances no profile generation | systemd-boot derives its default from the profile generation, so a reboot can bring a host back on an older configuration. Pin it by hand after a deploy: `nix-env -p /nix/var/nix/profiles/system --set <closure> && switch-to-configuration boot` |
| Nothing may write shell commands into the firewall | the policy is data, projected into the firewall rule options under nftables, which renders and applies one ruleset atomically. A command-shaped policy once flushed a zone NAT mid-reload and left a withdrawn rule in the chain forever |
| A public name gets its certificate only once the name exists in DNS | the CA's resolvers cache the answer it saw before the name was created, so a challenge can keep failing until that cache expires - the zone's SOA minimum, 1800 s here. Order a deployment that introduces a public name the other way round - record first, vhost second - and read the ACME log instead of the site's silence |
| The Bluetooth adapter on `hom-srv-01` can return on a different `hci` index | a replug can bring it back as `hci1` while Home Assistant still looks for `hci0`, leaving the integration in `setup_retry` until the service restarts |
| An OIDC identity link can move under a service | a changed `auth_id` makes the service read the login as a new account and the sync fail. Repair the one row, never delete the user - and derive role names from the publication (`adminGroups`), because a hand-written name that does not exist silently makes everyone a Viewer |
| A `nix-openclaw` bump can need a database migration that no check sees | `nix flake check` proves the closure builds, not that the gateway's schema matches its store. The migration lives in `/var/lib/openclaw` and the flake applies none, so a bump passes CI and fails at startup. `openclaw doctor` reports and applies the migration; it is written for non-Nix installs, so run it deliberately - a green check is not proof the gateway starts |

## 8. Maintaining the fleet

`.github/workflows/update.yml` updates `flake.lock`, runs the manifest updater, checks the flake and
builds every inventory host before committing. A failed preparation or host build prevents publication;
the workflow stages the whole working-tree change the updater produced and carries it as one patch, so it
keeps no list of manifest paths of its own.

```fish
nix run .#update-custom-packages                 # discover and update every manifest
nix run .#update-custom-packages -- composio     # a single package
```

Manifests under `packages/custom` and `features` select their upstream with `upstream.type` (release,
revision, PyPI, npm, GitHub release). Source updates measure fixed-output hashes
from the package derivations and verify them with a second build; `github-release` can select exactly one
named asset via `upstream.assetTemplate`. The mutable `latest` download is never a package source. A
failed refresh restores the previous manifest and leaves errors on stderr.

## 9. The agent workspace

### OpenClaw

The native OpenClaw gateway is assigned to `cld-ops-01`, alongside the Attic binary cache.
`my.features.services.openclaw.gateway` wraps the official `nix-openclaw` NixOS module. It runs
as the `openclaw` system account, stores its state in `/var/lib/openclaw`, and publishes
`https://openclaw.vyrx.de` through the ingress. The native listener includes loopback for local CLI
administration; the endpoint contract admits remote traffic only from the ingress over WireGuard.
The publication uses the standard
Authentik forward-auth contract, provisioning its provider, application and primary-user audience.
OpenClaw trusts only the ingress address and its overwritten `X-Authentik-Username` header; its
allowlist and session administrator grant derive from the primary username. Authenticated browser
devices are enrolled automatically with limited persistent grants. The administrator scope is granted
only to the verified owner's session. Client identity headers are stripped before forward auth.

Single-use `/j/*` enrollment links, credentialed `/__openclaw__/worker` connections, the
`/__openclaw__/worker-bundle/*`, `/__openclaw__/worker-transfer/*` and
`/__openclaw__/worker-bootstrap/*` artifact routes, and non-browser WebSocket upgrades bypass
browser SSO; OpenClaw verifies their own short-lived bootstrap, worker or paired-device credentials.
The artifact routes are plain HTTP GETs, so they need their own exemptions; the WebSocket bypass
does not cover them. The direct-local administrative CLI uses a separate password fallback, unavailable to
proxied requests. This password and the OpenCode Go, OpenRouter and OpenAI API keys come from SOPS at
runtime and never enter the Nix store. Shared Gateway tokens are incompatible with trusted-proxy mode
and are not configured.

The default interactive model is GPT-6.1 Sol through OpenAI; delegated work and background
maintenance use DeepSeek V4.1 Flash through OpenCode Go. Both use the native OpenClaw runtime.
Model selection uses the dynamically discovered provider catalog with an unrestricted model policy.
The interactive OpenAI model carries an explicit `agentRuntime.id = "openclaw"` binding because
paired-node session creation has no Codex app-server owner, so an implicit runtime would fail.
OpenAI provider auth is `oauth`: with the embedded runtime, an eligible Platform key otherwise wins
over the ChatGPT Plus profile and bills API credits, while an expired subscription now fails closed.
The gateway's ordered `opencodeSubscriptions` list provisions stable, named auth profiles through
OpenClaw's supported secrets-plan CLI before startup. Profiles store environment SecretRefs; API keys
remain in SOPS and the runtime environment. The importer uses a temporary config copy because the
upstream CLI invokes its config writer even for auth-store-only plans; the gateway's Nix config
remains immutable. `cld-ops-01` prefers `subscription-2` and falls back to
`subscription-1`, using `ai/opencode_api_key_2` and `ai/opencode_api_key` respectively. OpenClaw owns
session affinity and cooldowns, and rotates same-provider profiles on eligible quota, billing, auth
and transient failures. Exhausting both subscriptions surfaces an error; no fallback model is substituted.
Automatic session affinity can keep a healthy fallback selected after the preferred account recovers.
Provider-specific reset times are used only when OpenClaw recognizes them; no monthly reset date is
invented. An explicit per-agent auth-order override takes precedence over the declarative default.
The service and administrative CLI receive both credentials.
The `web_search` tool runs against the fleet's SearXNG instance. The `searxng` runtime plugin is
pinned through `nix-openclaw` and loaded by store path, so plugin installation stays outside the
immutable config, and the provider is selected explicitly. A co-located gateway queries loopback,
a remote gateway the provider's overlay address; the instance's machine-facing allowance already
covers that path while browser traffic keeps the Authentik gate. The instance must keep the JSON
API enabled.
Client file and image uploads are explicitly enabled (`gateway.uploads.enabled`); the runtime
default is enabled as well, and the authored value keeps configuration surfaces honest.
Widgets and MCP Apps use `sandbox.openclaw.vyrx.de` as a separate HTTPS origin. Its publication
routes only to the sandbox listener (gateway port plus one), reachable from the ingress over
WireGuard. The sandbox serves the public isolation shell and renderer assets without SSO;
private widget documents arrive through the authenticated gateway connection. The main UI and
gateway APIs retain their Authentik gate.
Portals publish temporary application previews under `*.preview.openclaw.vyrx.de`.
The namespace and its base login host use Authentik domain-level forward auth restricted to
the primary user. Each preview additionally retains OpenClaw's portal bearer/cookie gate.
The ingress presents a dedicated wildcard certificate and strips Authentik identity headers
before forwarding application traffic. A socket proxy reachable only by the ingress over
WireGuard connects to OpenClaw's loopback portal listener. Cloudflare publishes the wildcard
name and the base host it aliases; the fleet resolver answers both per plane, expanding the
wildcard through an RPZ CNAME onto the plane-specific address, so a preview opened at home
stays on the mesh. Application ports stay private.
Custom Plugin UI is enabled for trusted installed native plugin views; Host Desktop remains off.
Composio connects external apps (mail, calendar, chat, tickets, source control) through the local
Composio CLI. The pinned ClawHub runtime plugin ships the reviewed skill and routing hook, and its
conversation-access grant is authored explicitly; the CLI is packaged from the official
`@composio/cli` release and prepended to the exec PATH. CLI sign-in and connected
accounts are runtime state in the service account's home, not Nix. Provenance diagnostics for
Nix-loaded plugins are expected and informational.
The GitHub CLI is installed for the gateway process and the exec path. The gateway
uses the sops `users/<primary>/github_pat` credential in two roles: an explicit
`gateway.controlUi.github.token` SecretRef for project discovery and private
checkout, and a managed `tools.github` identity whose private `gh` profile is
rebuilt from the same SOPS value before the gateway starts. The profile id is
the only identity value in Nix; the credential never enters the store. Worker
turns receive the managed identity through their launch envelope, and the
declared Git author matches the service's `GIT_CONFIG_GLOBAL` identity.
The bundled Workboard plugin provides local Kanban boards for agent-owned cards and rule-based
session views; its boards live in gateway state, not Nix.
The node-workspace plugin publishes one explicitly selected directory from the gateway to a paired
node and returns selected changes after a preview. It is one package with two halves: the gateway
registers the agent tools, and every node host loads the same plugin root and runs the `nodews.*`
commands in its own process. `packages/custom/openclaw-node-workspace` builds it from a pinned
revision with `npmDepsHash`, and both sides load that store path; the gateway also allows the five
commands, which are all classified dangerous and therefore reachable only through that list. The
plugin speaks one protocol version, so the gateway and the nodes must run the same revision; a bump
changes the store path on both sides and is one change, not two. Each side declares only its own
config namespace: the gateway authorizes a local path against the calling session's workspace - the
boundary OpenClaw already hands to every tool - and a session without one falls back to the agent
workspace; the node publishes inside its own agent workspace. A push never replaces an existing
destination, a return never deletes and never overwrites a file that changed on both sides, and a
returned project is node-authored content: building or running it executes code the node chose. The
plugin's own repository carries the protocol, the security model and the recovery rules.
The built-in memory engine uses `openai/text-embedding-3-small` through OpenRouter. Search and
cross-conversation recall are explicitly enabled with `memory` and `sessions` as sources. Active
Memory is enabled in `escalate` mode for eligible private direct and explicit UI conversations;
deeper model-based recall runs when recall intent lacks a strong deterministic memory match.
Private transcript recall stays within the same agent. Indexing and nightly dreaming retain
OpenClaw's maintained defaults. Workspace memory, personality and personal working instructions remain runtime-owned
and are edited through OpenClaw. The delegation policy below is the managed exception.

Automations are enabled. Heartbeats run hourly with lightweight context in isolated sessions;
their delivery target is `none` because the installation has no external messaging channel.
Heartbeat results remain internal; this does not establish browser push or mobile notifications.
Recurring tasks and reminders are managed through OpenClaw's automations UI or CLI, not Nix.
Dreaming and other built-in maintenance jobs use the same scheduler with explicit background
model selection.
### Delegated work and model ownership

The gateway module separates the interactive `model`, `subagentModel` (defaults to
`model`), `backgroundModel` (defaults to `subagentModel`) and `utilityModel` (defaults to
`backgroundModel`). The host chooses concrete provider references once. `cld-ops-01` uses
Sol for interaction and DeepSeek for workers, background work and short internal utility
tasks such as session titles, progress narration and activity recaps. Same-agent workers use
their configured default even when the parent session overrides its model. Explicit spawn
overrides remain possible.

Native subagents start with medium thinking and an eight-worker concurrency ceiling.
The ceiling is not a target: independent scopes, provider throughput and integration
cost decide actual parallelism. Native settings can be overridden through the existing
`settings` option; there is no second routing engine or mandatory planner/reviewer team.
No model fallback chain is configured.

The [delegation policy](../features/services/openclaw/gateway/policy/AGENTS.md) is the
canonical behavioral contract. The gateway materializes it before startup as a regular
file at `<workspace>/.openclaw-policy/AGENTS.md`. The native `bootstrap-extra-files` hook
loads it alongside personal instructions. A Nix-store symlink is not suitable because
extra bootstrap files must resolve inside the configured workspace. Native hook discovery
also rejects hardlinked metadata, which occurs in the optimized Nix store. The service
therefore materializes the upstream `HOOK.md` and a one-line re-export of its unchanged
handler under `.openclaw-policy/hooks`, registered through native `load.extraDirs`.
Only these explicitly managed files are replaced; personal `AGENTS.md`, `USER.md`,
memory and learned skills are not regenerated. Policy changes alter the service unit and therefore follow normal nod
activation and rollback. They do not depend on a skill being selected for a turn.

The worker skill bundler rejects hardlinked files, including the identical files linked by
`auto-optimise-store` in the Nix store. Before each start, the Gateway copies the package's `skills`
and `custodian-skills` into its private systemd runtime directory `/run/openclaw-skills` and sets
`OPENCLAW_BUNDLED_SKILLS_DIR` to its `skills` subdirectory. OpenClaw derives the custodian directory
from that sibling layout. These are ordinary runtime copies, not links; systemd removes them when
the service stops, and a restart refreshes them from the selected package. Personal and learned skills
are untouched, and neither OpenClaw nor its hardlink checks are patched. Home Manager's upstream
skill materialization covers declared user/plugin skills, not these built-in package trees.

Plugin skills have the same restriction. OpenClaw publishes generated symlinks under
`/var/lib/openclaw/plugin-skills`; replacing those links would conflict with its discovery lifecycle.
The Gateway therefore also copies the browser, canvas and Composio skill trees into its runtime
directory and uses service-private read-only bind mounts at their original store paths. Native
plugin activation, discovery, precedence and generated symlinks stay unchanged, and the host's
Nix store is untouched. The materializer runs first: systemd skips the initially absent bind sources
for that command, then installs the mounts for subsequent commands and the Gateway. A copy failure
aborts startup. Additional store-backed plugin skill roots need the same declaration in
`pluginSkillTrees`; personal and learned roots are not mounted or replaced.

This addresses skill resource preparation, not every worker failure. Session capability-policy
preparation and completed node turns are separate runtime boundaries; passing the skill reader
does not verify them.

The Gateway package backports upstream [#194540](https://github.com/openclaw/openclaw/pull/194540)
for worker search-policy preparation. It resolves admitted web-search availability first and wraps
only the synchronous policy call in the existing capability-read preparation owner; tool admission
and permission checks are unchanged. `packages/custom/openclaw-gateway-worker-fix` patches the
installed Gateway graph, not the sealed worker archive or the nodes' supervisor package. Its build
rejects an already-prepared call with an explicit removal instruction, and rejects unfamiliar call
shapes rather than silently skipping the repair. When the repair ships upstream, remove that
package and restore `pkgs.openclaw-gateway` in the Gateway feature; no version-number guess or
runtime mutation is involved.

Remote work uses native node capabilities or session placement, not a separate executor account
or custom remote-exec synchronization tool. End-to-end worker execution must be verified separately
from skill resource preparation.

Skills supply task-specific procedures, not duplicate routing rules. Memory records
preferences and decisions, not technical defaults. Existing sessions and auth profiles
remain runtime state. Check actual bootstrap context for both main and isolated child
runs, including execution in a project folder; lightweight contexts may filter files.

Heartbeats and memory dreaming select `backgroundModel` explicitly. Ordinary runtime
automations must set their agent-turn model to the generated `background` alias; a
missing job override otherwise inherits the agent model. Existing jobs are inspected
and updated through the native automations tool, not rewritten by Nix or a database
script. Keep their schedule, ownership, delivery and task text unchanged.

For verification, evaluate the flake gate and validate the rendered native config.
After nod activates it, verify the managed regular file, retained personal files,
actual child model and task result, automation model overrides, and native prompt
injection. Subscription allowance and useful parallel throughput require measurement
on real tasks; a schema check does not establish either.


Browser and native-app Talk use OpenAI `gpt-live-1` with voice `marin` through the Gateway-owned
realtime relay. The relay supports Android and the browser without exposing the Platform key to
clients. GPT-Live delegates work to the interactive agent through `agent-consult`.
The speech locale is German and speech interruption is enabled. Non-realtime speech playback retains
OpenRouter `google/gemini-3.1-flash-tts-preview` with voice `Kore` as its configured provider.
Client microphone permission, audio playback and billable voice sessions require an actual client
session to verify.

Gateway data participates in the host's Restic backup.
The gateway can launch headless Chromium with its own persistent `openclaw` browser profile.
Browser routing prefers the gateway; an explicit node selection uses that device's browser proxy.
Server nodes also provide headless Chromium with a persistent `openclaw` profile, launched on demand.
Graphical nodes provide a separate managed Google Chrome profile (`openclaw`) and an attach-only
`user` profile for the primary user's existing Chrome session. The latter uses OpenClaw's packaged
Chrome DevTools MCP and requires remote debugging enabled at `chrome://inspect/#remote-debugging`
plus approval of Chrome's connection prompt. Managed PC browsers use the desktop session when
available and OpenClaw's headless fallback otherwise. Browser control and CDP remain on loopback;
node browser requests travel through the authenticated node connection.
Inspect the service with `journalctl -u openclaw-gateway`; administrative CLI operations run as the
service account through `sudo openclaw-gateway-admin <command>` on the gateway host.

`my.features.services.openclaw.node` enables a native Home Manager user service on `cld-edge-01`,
`hom-srv-01`, `hom-wrk-01` and `mob-nb-01`. The gateway host runs no node service. Each node's
gateway endpoint derives from the fleet's unique enabled gateway. Each node
keeps its own pairing identity under `~/.local/state/openclaw-node`, separate from other OpenClaw
profiles. The ingress host resolves the gateway name to its inventory public IPv4 address locally,
so its own node has a distinguishable client address at the trusted proxy boundary. The node runs
with the primary user's filesystem permissions. Enrollment uses a new,
single-use URL for each device:

```bash
# On cld-ops-01:
sudo openclaw-gateway-admin devices join-code
# On the target PC, as its primary user:
openclaw-node-connect '<join-url>'
```

The helper takes exactly one join URL or setup code: `--help` and any other flag print the usage
and exit without touching the service. It stops the node unit for the duration of the enrollment -
a foreground node and the service share the state directory - and runs itself in a transient scope
beside the unit, so that stop cannot interrupt the enrollment. After enrollment, stop the
foreground connection with Ctrl-C; the helper starts the Home Manager service using the saved
device credential. Inspect it with `systemctl --user status openclaw-node` and
`journalctl --user -u openclaw-node`.
The phone uses the central gateway's Control UI; mobile node enrollment uses the platform's
companion app and exposes that platform's supported device capabilities. Office computers enroll
against the same gateway with their platform's node host. A device outside the mesh uses the same
public TLS endpoint and requires no inbound node port.

The official flake pins OpenClaw `2026.10.4`. Native node session hosting uses managed workspaces
in this release; the newer existing-device-folder picker is not included. Node identity and
pairing credentials remain runtime-owned; Nix owns the services, node hosting consent and settings.

Node file access is fleet-wide and deliberate. The File Transfer plugin classifies all six of its
node commands as dangerous, so no platform default carries them and `gateway.nodes.commands.allow`
names each one; the plugin's path policy admits `/**` for reads and writes on every paired node,
follows symlinks and takes no per-call approval, because the Nix-owned config file is immutable and
cannot persist a standing grant. The plugin builds directory archives with the hardcoded FHS path
`/usr/bin/tar`, which the node materialises from the Nix store. The gateway host runs no node
service, so this scope never reaches the gateway's own state directory.

The two personal computers also capture from their attached camera. Their nodes enable the Linux
node plugin's camera capability, carry FFmpeg on the node service PATH and belong to the `video`
group for `/dev/video*`; `gateway.nodes.commands.allow` carries `camera.snap` and `camera.clip`,
while `camera.list` is a Linux plugin default. A clip carries the default audio source unless the
caller disables audio, so camera access includes the microphone. Computer control stays off: the
bundled CUA driver implements X11 only, and the fleet's Niri session is native Wayland, so an
enabled provider would advertise `screen.snapshot` and `computer.act` and refuse every call.
Desktop screenshots on those hosts run through shell execution instead.

## OpenChamber workspaces

`my.features.dev.openchamber.enable` installs OpenChamber Desktop on `hom-wrk-01` and
`mob-nb-01` (`role = "desktop"`) and a headless OpenChamber runtime on `hom-srv-01` and
`cld-edge-01` (`role = "server"`). `role = "both"` runs the desktop and the headless server on
one host, with different ports. Clients use the desktops for local work and the server runtimes for
work that must outlive a laptop.

The desktop's network port is declared once by the feature's `port` option (default 7337).
Activation first checks that the port is free or already served by a running desktop with the
`desktop` runtime; another listener fails the switch instead of letting the app fall back to a
random port. Activation merges the port and network access into writable desktop settings. Existing
UI passwords are retained; if `uiPasswordSecret` names a SOPS secret, its value becomes the desktop
password, otherwise a fresh device gets a random password stored only in its mode-0600 settings file.
The endpoint contract admits the other enabled OpenChamber hosts and every inventory host with
`hostType = "client"` over WireGuard; that includes the phone without giving it a NixOS host entry.
The feature's `autostart` option (default on) writes the XDG autostart entry at
`${XDG_CONFIG_HOME}/autostart/openchamber.desktop`; the desktop's own checkbox reflects the file's
existence, and the next activation restores an entry disabled in the app. The entry points at the Nix
wrapper and the pinned OpenCode CLI is also on the session PATH, because the desktop rewrites
`Exec` to its raw Electron path at startup. A device's desktop must be running to use its
workspace.

### One server, thin clients

The server role is the session authority. Desktop clients seed one host per server-role host
(`nixfiles-server:<name>`) and default to `defaultHost` (the home server), so a session starts on the
server, not locally; `local` remains only as the offline fallback.

Enrollment runs server → desktop, because desktops do not have a primary-user SSH path to the
servers while servers do. `openchamber-server-enroll` (oneshot at boot, then every ten minutes) mints
one client token per declared desktop through the server's UI password and delivers it over SSH as
the primary user; `openchamber-fleet-pair --set-server-token` verifies it against
`/api/config/settings` and writes the host entry. Tokens travel over stdin, never argv or logs, and a
removed desktop is revoked through the existing pending-revocation path.

Mobile clients pair with `openchamber-server-pair` on the server instead of the desktop helper.

The headless role runs `openchamber serve --foreground --port 7338 --lan --api-only` as the primary
user through the `openchamber-server` systemd unit: without `--foreground` the command daemonises
and exits, so the unit would report a successful stop instead of a running server. It restarts
always, which turns an unexpected exit into a visible restart loop rather than a silent stop, and
generates a mode-0600 UI password once at
`${XDG_STATE_HOME}/openchamber/server-ui-password`, or reads `server.uiPasswordSecret`; a SOPS
secret reaches the process through `LoadCredential`, never argv. The endpoint contract admits the
desktop peers and the phone over WireGuard. `openchamber-server-pair` on a server prints a
one-time QR/link for a desktop or phone; the client imports it in Settings → Remote Instances. The
desktop helper `openchamber-mobile-pair` does the same for a phone connecting to a desktop. Pairing
links are single-use secrets and are never written into the Nix store.

Native device tokens connect desktops directly over WireGuard. `openchamber-fleet-pair --issue`
runs on the target over the existing operator SSH identity and creates one `desktop` client token
through the target's local admin API (`POST /api/client-auth/clients`); the source stores that token
in `desktopHosts`. Only initial enrollment uses SSH. Before issuing, the target ensures its own
`desktop-local` token: if it is missing or rejected, it logs in over loopback with the stored UI
password and creates a permanent `desktop-local` client, so enrollment does not depend on a manual
UI login. UI passwords and local desktop tokens stay on the target. Subsequent connections need
neither SSH nor a relay. A user timer retries enrollment one minute after login and five minutes
after each completed attempt; its oneshot process starts no server and exits after checking the
peers. An offline peer keeps its saved entry. A revoked token is reported and is not automatically
replaced. Remove the managed local entry to request enrollment again, or pair it in the app. The
operator SSH identity must be available for enrollment, for example through an unlocked SSH agent.
The Nix-managed IDs use the `nixfiles:` prefix; personal connections remain untouched.
`defaultHost` selects a peer or `null` (Local) at desktop startup; an offline peer falls back to
Local.

The switch removes managed SSH entries, discards their old tunnel tokens once and registers native
host addresses from the inventory. Native tokens are retained on later switches. Both settings writers
take an exclusive `flock` on `.settings.lock` and atomically replace only a changed document; a peer
that disappears from the declaration is queued for best-effort revocation on the next enrollment
pass. Electron serialises its own writes only inside its process and upstream exposes no external
settings API, so avoid simultaneous device edits during activation or enrollment. Restart the desktop
after migration to release its old SSH sessions.

Go subscriptions are independent of device enrollment. They are listed in
`inventory/opencode-subscriptions.nix`, shared with OpenClaw; the personal-computer role selects the
list through `subscriptions`, and the two headless server hosts select it in their own configuration.
The `openchamber-accounts` oneshot runs as the primary user at boot and when its declaration or SOPS
keys change. It reconciles OpenCode's own credential store with the supported `auth list`,
`import`, `switch` and `logout` commands. Every command uses `--standalone`: its private helper
ends with the command and does not create a background service. Key values reach `auth import`
through stdin and never enter the Nix store or process arguments. Stable IDs preserve selections;
rotated keys are imported before an active declared account is switched and retired declared
credentials are removed. Manually added accounts remain. The reconciliation writes into the
integration that already holds the declared keys and fails loudly rather than guessing on a device
that lists none; a first run prefers `opencode` and falls back to `opencode-go`, because a device
only exposes the integrations its provider catalog knows. Restart OpenCode in the app after changing
credentials if its running integration still shows the previous state. The feature seeds
`accountSwitchProviders: ["opencode-go"]` only when the key is absent; an existing preference remains
owned by OpenChamber.

Account switching defaults to the `opencode-go` provider. OpenChamber rotates stored credentials when
quota or budget exhaustion, or a rate limit of at least a minute, stops a turn. Reset hints control
cooldowns; without a hint the default is one hour, and cooldowns are forgotten on restart. The
active credential belongs to a credential integration, not an individual session. OpenCode shows
its Console as `opencode` and its Go plan as `opencode-go`; which of the two carries the declared
keys depends on the provider catalog the device knows, so the reconciliation follows the existing
store instead of naming one. Switching changes the account used by that integration. A separate
fallback model is an interactive preference; the feature does not configure one. OpenClaw and the
OpenChamber runtimes consume the same subscription limits and maintain independent cooldowns.

The pinned OpenChamber v2.8.0 does not include OpenCode's `provider.go-limit` in either failover
boundary by itself. `features/dev/openchamber/patch-limit-failover.py` adds it to the server
classifier and to the generated OpenCode plugin in one build phase, and fails when either upstream
block changes shape. `checks/openchamber-failover.nix` exercises both patch boundaries and rejects a
drifted shape. Without this patch the seeded `opencode-go` switch never fires for an OpenCode Go
quota exhaustion.

Every immediate directory in `features/dev/openchamber/plugins/` is merged into the app's own
built-in registry; an ID or directory collision with an upstream built-in fails the build instead of
replacing it. Its manifest and runtime assets are validated by OpenChamber's own package inspector
during the build. The manifest requires `openchamber.apiVersion: 1`, a non-empty semver `version`,
and `openchamber.id = openchamber-builtin-<directory>`; the older `panel.id` is accepted when
`openchamber.id` is absent, and both must agree when present. `contributes.panel` is optional:
service-only, background-only, page-only and `opencodePlugin`-only extensions are valid. Panel
entries must point at self-contained HTML with built scripts; service entries must be built JS.
App-shipped extensions trust the permissions declared in the repository and can be disabled in the
UI. Runtime extensions remain supported through Settings → Extensions and `/new-extension`; the
feature does not replace the writable extension catalog. See
[`plugins/README.md`](../features/dev/openchamber/plugins/README.md) for the package contract and how
to promote a runtime extension into the configuration.

`fleet-session-journal` is the panel-less fixture: it ships only a local service and a
`sessionEvents` subscription with content, appends each event to its private data directory, and is
disabled without deleting data. Built-in services run as the primary user with normal process access;
treat their code and data as trusted configuration. `fleet-opencode-tools` is the
`contributes.opencodePlugin` fixture: it adds the `fleet_runtime` tool through the managed OpenCode
config while the extension is enabled, and removes it when the extension is disabled.

Fleet is a normal OpenChamber runtime extension, not a built-in. The `openchamber-fleet` input
provides its portable `extensions/openchamber` package unchanged (ID `openchamber-fleet`); the
OpenChamber core is built without it. After the runtime is up, a server system service installs and
approves it through OpenChamber's official `/api/guests` install and capabilities routes; a desktop
user service does the same with the local app's client token. That desktop unit treats an app that is
not running yet as a deferred retry, so a headless switch does not fail Home Manager activation; its
timer installs the extension when the app starts. The installer approves exactly the capabilities the
package requests, so a version that widens its scope shows as needs-approval until the system
deploys the new package. Because the extension is not part of the app build, a Fleet
version bump changes only the small extension path and does not rebuild the OpenChamber core.
Every OpenChamber host also installs the `fleet` CLI and `fleet-agent`; `FLEET_AGENT_PATH` names the
stable system profile binary and `FLEET_SSH_PATH` names the packaged OpenSSH client.
Hosts are machine-level in `$XDG_CONFIG_HOME/openchamber-fleet/hosts.json`; a project selects
aliases in `workspaces/<project-id>.json`, so the extension works without Nix or a Nix host list.
The panel edits both local documents; nothing is written into the repository. A legacy `fleet.json`
is still read until the split project configuration exists.

The agent tools are `fleet_status`, `fleet_sync`, `fleet_exec`, `fleet_fetch`, `fleet_job_status`,
`fleet_job_cancel` and `fleet_recover`. Exec evaluates a host/cwd/env-key descriptor under `fleet.exec`
and OpenCode's `shell` permissions for the exact remote argv, fetch evaluates `edit` and
`external_directory`, and sync apply/recovery use dedicated Fleet actions. `fleet_exec` with `background: true` returns a job id and resumes the same session via
OpenCode's official synthetic-message API when the job finishes. Background jobs belong to the
running OpenCode runtime; restart, plugin unload and location eviction are reported as interruptions.

OpenChamber's optional shared `opencode serve --service` mode is not enabled. The pinned Nix CLI
registers its service under the channel-specific file while the v2.8.0 desktop client looks for the
generic one; enabling the toggle without aligning that would start a second unreachable daemon.

The upstream Nix build uses import-from-derivation for its Bun dependency catalog. Evaluation can
therefore build the converter. Keep the upstream nixpkgs/Bun pin with the OpenChamber input: its
OpenCode build requires the matching Bun runtime. The feature's server role is evaluated and built
with the same pin. Updates go through the repository gate and a server and desktop build before
activation; the failover patch guard must pass first.
