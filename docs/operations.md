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
nix run .#update-custom-packages -- opencode     # a single package
```

Manifests under `packages/custom` and `features` select their upstream with `upstream.type` (release,
revision, PyPI, npm, Obsidian, GitHub release, flake package). Source updates measure fixed-output hashes
from the package derivations and verify them with a second build; `github-release` can select exactly one
named asset via `upstream.assetTemplate`; `openai-desktop` reads OpenAI release metadata without executing
it and rejects missing or ambiguous lists. The mutable `latest` download is never a package source. A
failed refresh restores the previous manifest and leaves errors on stderr.

`upstream.type = "flake-package"` leaves source selection to `flake.lock` and declares
`dependencyAttributes`, a map of logical dependency names to fixed-output derivations. Hashes are measured
for the package build platform, not copied between platforms; an empty hash bootstraps a new platform and
a normal build then fails loudly with a mismatch. OpenCode uses this schema, with the fleet Bun package
checked against the upstream `packageManager` requirement - an unsupported version fails loudly rather
than accepting an unverified dependency tree.

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
proxied requests. This password and the OpenCode Go API key come from SOPS at runtime and never enter
the Nix store. Shared Gateway tokens are incompatible with trusted-proxy mode and are not configured.

The default model is DeepSeek V4.1 Flash through OpenCode Go, using the native OpenClaw runtime.
Recurring heartbeats and cron are disabled. Gateway data participates in the host's Restic backup.
Inspect the service with `journalctl -u openclaw-gateway`; administrative CLI operations run as the
service account through `sudo openclaw-gateway-admin <command>` on the gateway host.

`my.features.services.openclaw.node` enables a native Home Manager user service on `cld-edge-01`,
`hom-srv-01`, `hom-wrk-01` and `mob-nb-01`. The gateway host runs no node service. Each node's
gateway endpoint derives from the fleet's unique enabled gateway. Each node
keeps its own pairing identity under `~/.local/state/openclaw-node`, separate from other OpenClaw
profiles. The node runs with the primary user's filesystem permissions. Enrollment uses a new,
single-use URL for each device:

```bash
# On cld-ops-01:
sudo openclaw-gateway-admin devices join-code
# On the target PC, as its primary user:
openclaw-node-connect '<join-url>'
```

After enrollment, stop the foreground connection with Ctrl-C; the helper starts the Home Manager
service using the saved device credential. Inspect it with
`systemctl --user status openclaw-node` and `journalctl --user -u openclaw-node`.
The phone uses the central gateway's Control UI; mobile node enrollment uses the platform's
companion app and exposes that platform's supported device capabilities. Office computers enroll
against the same gateway with their platform's node host. A device outside the mesh uses the same
public TLS endpoint and requires no inbound node port.

The official flake pins OpenClaw `2026.10.4`. Native node session hosting uses managed workspaces
in this release; the newer existing-device-folder picker is not included. Node identity and
pairing credentials remain runtime-owned; Nix owns the services, node hosting consent and settings.

### OpenChamber

`hom-srv-01` runs the always-on OpenChamber instance the other devices pair with: a user service bound to the
overlay address `10.10.100.10:3000`, serving the API, and published as `chamber.vyrx.de` through
the ingress. Application API calls use device tokens; the publication keeps non-API routes behind fleet
single sign-on. A personal computer runs its own instance only while its session is
up, so the machine that never sleeps is the one to pair with.

PC and notebook receive their outgoing connections and individual grants through the declarative mesh
reconciler described in [Desktop](desktop.md). The server has no outgoing peers. Mobile connections are
paired manually and remain untouched by that reconciler. Mint a link on the target as the operator:

```bash
openchamber connect-url --port 3000 --server http://10.10.100.10:3000 --qr
```

`--server` is the address the link carries, and it is the overlay address on purpose: `OPENCHAMBER_LAN_URL`
names the same one, so the dialog and the command mint the same link, and a device on the mesh then reaches
the instance directly. Scan the printed code in the mobile app, or open the printed
`openchamber://connect?v=2&p=...` link on the machine that runs the desktop app. It is single use, expires on
its own and never carries the UI password; the device then holds its own token, listed and revocable under
*Settings - Remote Instances*.

Off the mesh, paired applications can use `https://chamber.vyrx.de` for API access. The instance runs in
API-only mode; this publication does not serve a browser workspace. Non-API routes require the
`infra-admins` single sign-on audience. A paired application sends no `Origin` on its
WebSocket upgrade, so the ingress hands that connection to the instance, which checks the device token
itself. The instance is bound to the overlay address, so a device that cannot resolve that address needs a
name it can reach - not the link above.

Two properties of the command are worth knowing before it runs. It writes a relay identity into
`~/.config/openchamber/relay-identity.json` when none exists: that file must never enter a backup or a
dotfile repository, and a new identity invalidates every earlier pairing. And it starts a server when nothing
answers on the port, so read the port before minting a link on a machine that should not be serving.
