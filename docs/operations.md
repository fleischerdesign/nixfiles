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
| Home Assistant carries OAuth backports for the MCP server | `packages/overlays/fix/home-assistant/` backports upstream PKCE metadata and frontend behaviour until 2026.10; the overlay applies them only while the version is older and warns once it is not, so a nixpkgs bump makes the files dead rather than breaking the build |
| A public name gets its certificate only once the name exists in DNS | the CA's resolvers cache the answer it saw before the name was created, so a challenge can keep failing until that cache expires - the zone's SOA minimum, 1800 s here. Order a deployment that introduces a public name the other way round - record first, vhost second - and read the ACME log instead of the site's silence |
| The Bluetooth adapter on `hom-srv-01` can return on a different `hci` index | a replug can bring it back as `hci1` while Home Assistant still looks for `hci0`, leaving the integration in `setup_retry` until the service restarts |
| An OIDC identity link can move under a service | a changed `auth_id` makes the service read the login as a new account and the sync fail. Repair the one row, never delete the user - and derive role names from the publication (`adminGroups`), because a hand-written name that does not exist silently makes everyone a Viewer |

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
revision, PyPI, npm, Obsidian, GitHub release). Source updates measure fixed-output hashes
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

Single-use `/j/*` enrollment links, credentialed `/__openclaw__/worker` connections and non-browser
WebSocket upgrades bypass browser SSO; OpenClaw verifies their own bootstrap, worker or paired-device
credentials. The direct-local administrative CLI uses a separate password fallback, unavailable to
proxied requests. This password and the OpenCode Go, OpenRouter and OpenAI API keys come from SOPS at
runtime and never enter the Nix store. Shared Gateway tokens are incompatible with trusted-proxy mode
and are not configured.

The default model is DeepSeek V4.1 Flash through OpenCode Go, using the native OpenClaw runtime.
Model selection uses the dynamically discovered provider catalog with an unrestricted model policy;
the default model does not impose a one-model restriction or an explicit per-model runtime binding.
The gateway's ordered `opencodeSubscriptions` list provisions stable, named auth profiles through
OpenClaw's supported secrets-plan CLI before startup. Profiles store environment SecretRefs; API keys
remain in SOPS and the runtime environment. The importer uses a temporary config copy because the
upstream CLI invokes its config writer even for auth-store-only plans; the gateway's Nix config
remains immutable. `cld-ops-01` prefers `subscription-2` and falls back to
`subscription-1`, using `ai/opencode_api_key_2` and `ai/opencode_api_key` respectively. OpenClaw owns
session affinity and cooldowns, and rotates same-provider profiles on eligible quota, billing, auth
and transient failures. Exhausting both subscriptions surfaces an error; the model stays DeepSeek.
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
The GitHub CLI is installed for the gateway process and the exec path; the GitHub identity stays
native (`gh` login as the service account), because a managed identity would write runtime config
that Nix ownership forbids.
The bundled Workboard plugin provides local Kanban boards for agent-owned cards and rule-based
session views; its boards live in gateway state, not Nix.
The built-in memory engine uses `openai/text-embedding-3-small` through OpenRouter. Search and
cross-conversation recall are explicitly enabled with `memory` and `sessions` as sources. Active
Memory is enabled in `escalate` mode for eligible private direct and explicit UI conversations;
deeper model-based recall runs when recall intent lacks a strong deterministic memory match.
Private transcript recall stays within the same agent. Indexing and nightly dreaming retain
OpenClaw's maintained defaults. Workspace memory, personality and working instructions remain
runtime-owned and are edited through OpenClaw.

Automations are enabled. Heartbeats run hourly with lightweight context in isolated sessions;
their delivery target is `none` because the installation has no external messaging channel.
Heartbeat results remain internal; this does not establish browser push or mobile notifications.
Recurring tasks and reminders are managed through OpenClaw's automations UI or CLI, not Nix.
Dreaming and other built-in maintenance jobs use the same scheduler and the default agent model.

Browser and native-app Talk use OpenAI `gpt-live-1` with voice `marin` through the Gateway-owned
realtime relay. The relay supports Android and the browser without exposing the Platform key to
clients. GPT-Live delegates agent work to the default DeepSeek model through `agent-consult`.
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
