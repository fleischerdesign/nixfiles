# VYRX 2.0 — Deployment & Network Cutover Runbook

> **Status:** Operational runbook (living document)
> **Audience:** Operators and autonomous agents. Everything needed to finish (or recover) the 2.0 rollout is here.
> **Companion docs:** `architecture.md` (the system and its vocabulary), `naming.md` (names and planes), `identity.md` (Authentik), `security.md` (the threat model), `embedded.md` (the device fleet), `practices.md` (how we work).
> **Emergency?** Jump straight to [§11 Emergency Recovery](#11-emergency-recovery--regaining-access).

---

## 1. Purpose

The 2.0 migration moves a historically grown setup ("hosts named after musicians", fragmented domains, `192.168.178.0/24`) onto:
- RFC 1178 host taxonomy and RFC 1918 zoning (`10.10.0.0/16`),
- declarative NixOS + Home Manager,
- a WireGuard mesh (`10.10.100.0/24`) as the transport, which also delivers the home LAN zones to
  roaming clients,
- `hom-srv-01` taking over LAN services (DHCP, DNS, NTP, gateway) from the FRITZ!Box.

This document is the **execution + safety guide**. It is deliberately explicit about **rollback and lockout avoidance**, because the rollout changes network services that can cut off the very access path you are deploying over.

---

## 2. Golden Rules (read before touching anything)

1. **Never remove your out-of-band path.** Before any network change you must have at least one working path that does *not* depend on the thing you are changing:
   - Public IP SSH (cloud hosts): `root@173.249.22.211`, `root@37.114.55.91`
   - the WireGuard mesh (`root@10.10.100.x`) — the only overlay; Tailscale was retired 2026-09-20
   - Wired LAN access + a client with a **static IP** in the affected subnet
   - Physical console / keyboard for home hardware; LAN web UI for FRITZ!Box and RE330
2. **The mesh is the transport.** Tailscale was removed on 2026-09-20; the four cutover criteria of
   §10 were measured first (every host on 2.0, handshakes on both hubs, `10.10.100.x` reachable, deploy
   targets resolving to reachable WG addresses). The home LAN reaches roaming clients for the zones
   that hold devices without an overlay identity (`announcedZones`, derived from the inventory);
   `my.topology.lanRouter` names the host that carries them - not a second router.
3. **Exactly one DHCP server per L2 segment.** Never run FRITZ!Box DHCP and `hom-srv-01` Kea DHCP at the same time on the same subnet.
4. **Never point DNS at a host that is not serving DNS yet.** FRITZ!Box DNS may only be set to `10.10.10.10` (Blocky) after Blocky answers queries.
5. **The FRITZ!Box is the WAN modem.** The declarative engine only manages its **DNS, DHCP toggle and port forwards** — *never* its LAN IP, subnet or Wi-Fi. Do not change those.
6. **Backups/rollback first.** Record the current generation and have a rollback path (see §7).
7. **Preview before activating.** `nod switch <target> --dry-run` / `nod plan <target>` and `git status` clean.
8. **Home network changes are maintenance windows.** Do them while physically on-site (or with guaranteed wire/LAN access).

---

## 3. Cluster Quick Reference

### 3.1 Hosts

| Host | Role | Zone | Primary IP | WireGuard | Public IP | Domain |
|---|---|---|---|---|---|---|
| `cld-edge-01` | server (identity/ingress) | mesh | 10.10.100.1 (WG) | relay hub | `173.249.22.211` | `edge.vyrx.de`, `auth.vyrx.de` |
| `cld-ops-01` | server (observability/AI) | mesh | 10.10.100.2 (WG) | relay hub | `37.114.55.91` | `ops.vyrx.de` |
| `hom-srv-01` | server (LAN core, media) | infra | `10.10.10.10` | 10.10.100.10 | – | `srv.lan.vyrx.de` |
| `hom-wrk-01` | desktop (Niri/Axis) | corp | `10.10.20.10` | 10.10.100.20 | – | `wrk.lan.vyrx.de` |
| `mob-nb-01` | notebook | corp (roaming) | DHCP | 10.10.100.30 | – | – |
| `hom-rt-01` | FRITZ!Box (WAN modem) | infra | `10.10.10.1` | – | – | `rt.lan.vyrx.de` |
| `hom-ap-01` | TP-Link RE330 AP | infra | `10.10.10.20` | – | – | `ap.lan.vyrx.de` |
| `hom-rly-01..08` | Sonoff relais (ESPHome) | iot | `10.10.30.11..18` | – | – | `rly-0X.iot.vyrx.de` |

> **Target vs. reality:** this table lists the **2.0 target identity**, which every host now runs. The narrative sections 7 and 8 that follow are the *record of the cutover* (state as of 2026-09-19, when only `cld-edge-01` was migrated); they are kept as history, not as instructions.

### 3.2 Subnets (`my.topology.subnets`)

| Zone | CIDR | VLAN | Trust | Notes |
|---|---|---|---|---|
| `infra` | `10.10.10.0/24` | 10 | infra | Servers, FRITZ!Box, AP. Gateway via `10.10.10.1`. |
| `corp` | `10.10.20.0/24` | 20 | corp | Workstations. Gateway via `hom-srv-01` (`10.10.10.10`). |
| `iot` | `10.10.30.0/24` | 30 | iot | ESPHome / smart home. Gateway via `hom-srv-01`. |
| `mesh` | `10.10.100.0/24` | – | mesh | WireGuard overlay (IPv4). |
| `mesh-ipv6` | `fd10:1000:100::/64` | – | mesh | WireGuard overlay (RFC 4193 ULA). |
| `guest` | `10.10.99.0/24` | 99 | guest | Internet-only. |

### 3.3 Overlay — WireGuard only (Tailscale retired 2026-09-20)

The tailnet was removed once its four cutover criteria (§10) were met and measured. Remaining tailnet
devices exist only in Tailscale's own admin console and must be deleted there; nothing in this
repository or in the fleet reads them.

The overlay is `10.10.100.0/24` (`fd10:1000:100::/64`), relay hubs `cld-edge-01` and `cld-ops-01`, and
every host peers with both. NetworkManager gives wifi a route metric of 600, so the mesh interface
carries 1000: a prefix the host can reach directly always wins, and the tunnel is used only when the
LAN is elsewhere.

---

## 4. Connectivity & Transport Model

### 4.1 Transport priority

| Situation | Use |
|---|---|
| Cloud host, any time | **Public IP** (`root@<public-ip>`) — always-on lifeline |
| Everything else | **WireGuard** (`root@10.10.100.x`) — all five hosts, hubs and spokes alike |

### 4.2 `nod switch` / `deploy` target the WireGuard IPs — and work

The flake's `deploy.nodes.<host>.hostname` is the host's `wireguardIpv4`, and the legacy `tailscaleIp`
shim that used to stand behind it is gone. All five hosts answer on those addresses (measured
2026-09-20: `ping` and `ssh` on `10.10.100.1`, `.2`, `.10`, `.20`, `.30`), so `nod switch <host>` no
longer times out at the closure copy stage.

`deploy` has `autoRollback = true`; `nixos-rebuild` does **not**, so keep out-of-band access ready — on
the cloud hosts that is the public IP, which never depends on DHCP, DNS or the mesh.

The flake `deploy.nodes.<host>.hostname` is computed as:

```nix
hostConfig.config.my.topology.hosts.${name}.wireguardIpv4
  or hostConfig.config.my.features.system.networking.topology.hosts.${name}.tailscaleIp;
```

The topology "legacy shim" sets `tailscaleIp = h.wireguardIpv4`, so **both resolve to the WireGuard IP**. `nod` therefore always targets `10.10.100.x`. While the WG peers are not handshaking (see §10), `nod switch <host>` times out at the closure copy stage.

**Workarounds during the transition (pick one):**
- **A (recommended now):** deploy with `nixos-rebuild` and an explicit reachable address:
  ```bash
  nixos-rebuild switch --flake .#<host> --target-host root@<public-ip|tailscale-ip|lan-ip>
  ```
- **B:** fix `deploy.nodes.<host>.hostname` to prefer the public IP (cloud) / Tailscale MagicDNS (`<host>.<tailnet>.ts.net`) and keep WG as a later switch.
- **C (auto-rollback, if wanted):** `deploy-rs` with an explicit `--hostname` override, since the CLI is not installed locally:
  ```bash
  nix run github:serokell/deploy-rs -- .#<host> --hostname <public-ip|tailscale-ip>
  ```
  `deploy` has `autoRollback = true` in the flake; `nixos-rebuild` does **not**, so keep out-of-band access (VPS console) ready.

`nod switch <host> --dry-run` and `nod plan <host>` are safe and still useful for planning.

### 4.3 Onboarding a roaming client (a phone)

A device that cannot run NixOS joins the mesh as a node with no NixOS configuration: one
`my.topology.hosts` entry with `hostType = "client"`, an overlay address and its WireGuard public key.
The relays add it as a `/32` peer; the primary hub carries the mesh and the home LAN zones for it.

Its private key lives in SOPS at `infra/wireguard/<name>_private_key`, like every host's. The host that
declares `my.features.system.networking.wireguard.clientConfigs = [ "<name>" ]` (currently
`hom-wrk-01`) renders the wg-quick file from the topology at activation, with the private key injected
by sops-nix - Nix cannot read a SOPS value at build time. Scan it once:

```bash
sudo qrencode -t ansiutf8 -r /run/secrets/rendered/wg-<name>.conf
```

Use `-r`, not a shell redirect: the file is root-only, and `< file` would be opened by the operator's
shell before `qrencode` runs.

The profile carries the resolvers of the mesh as **`DNS =`**, and it needs them: measured 2026-09-22,
a phone whose VPN network had no DNS server could not resolve the name it was told to use for private
DNS, so the network was reported `PrivateDnsBroken` and without `INTERNET` while the underlying network
was fine - the phone's push connections stopped being rebuilt on the network it was actually using, and
notifications only arrived when the tunnel was switched off. The line is the *bootstrap*; the resolver
the device actually uses is still a setting of its own - **Android: Settings → Network → Private DNS →
hostname `dns.vyrx.de`** (iOS needs a configuration profile, `wg-quick` on Linux takes `DNS =` per
interface). Both are needed and neither replaces the other: private DNS is global and covers the networks
the tunnel is not up on, including a foreign WLAN where the setting is the only reason the device still
asks us. It is a precondition, not an automatism: one setting per device, invisible if it silently turns
off (measured 2026-09-21: it had). Verify it on the device, not in the config: a blocked name must answer
`127.0.0.1` (`00000.uno`) where a public resolver answers a real address, `cld-edge-01` must show the
client on port 853, and the VPN network must carry a DNS address instead of an empty list.

The peers, addresses, DNS and routes in that file are derived, not typed: the same `relayPeersFor`
function builds the NixOS spokes' peers. Revocation is the inverse, plus the key rotation in
[security.md §3.2](security.md).

---

## 5. Pre-flight Checklist (every deploy session)

- [ ] `git status` clean; 2.0 changes committed (`git log --oneline -5`).
- [ ] `nix flake check` passes (eval all hosts + statix + deadnix).
- [ ] Required SOPS secrets present and decryptable on the target host:
      `services/authentik/*`, `services/fritzbox/password`, `services/wifi/ap_password`,
      `infra.*_private_key` (WireGuard), `services/cloudflare/*`.
- [ ] Backup done: FRITZ!Box config export (UI: System → Backup), current NixOS generation recorded
      (`readlink -f /run/current-system`).
- [ ] Out-of-band access confirmed for the target (public IP / mesh overlay / wired LAN / console).
- [ ] For network changes: a second device with a **static IP** in the affected subnet is online.
- [ ] Maintenance window known (home Wi-Fi / DHCP changes are user-visible).

---

## 6. Deployment Order & Dependencies

```
Phase 0  Repository + secrets verified, Tailscale up, backups taken
Phase 1  cld-edge-01        (DONE)  – identity/ingress
Phase 2  cld-ops-01                 – observability/AI, second relay hub
Phase 3  hom-srv-01                 – LAN core; ***network cutover, §8***
Phase 4  hom-wrk-01                 – desktop
Phase 5  mob-nb-01                  – notebook
Phase 6  nodTargets (§9): fritzbox (hom-rt-01), tplink-ap (hom-ap-01), esphome relays, cloudflare
Phase 7  WireGuard cutover (§10): verify all handshakes, then retire Tailscale
```

Rationale: servers first (they carry contracts/outposts/relay hubs), the home LAN core before the clients that depend on its DHCP/DNS, clients afterwards, and the embedded network devices last (they change connectivity, so they need the servers healthy for rollback).

---

## 7. Per-Host Runbook

### 7.0 Common pattern

```bash
# from /etc/nixos on the admin workstation
HOST=<host>; ADDR=<public-ip|mesh-ip|lan-ip>

nod plan "$HOST"                                   # optional preview
nixos-rebuild switch --flake ".#$HOST" --target-host "root@$ADDR"

# verify
ssh root@$ADDR 'systemctl --failed'
ssh root@$ADDR 'readlink -f /run/current-system'
```

**Rollback (per host):**
```bash
nod rollback "$HOST"                                # or:
ssh root@$ADDR 'nixos-rebuild --rollback switch'
```
Worst case: reboot and select the previous generation in the bootloader (GRUB).

### 7.1 cld-edge-01 — DONE
Identity/ingress host. Authentik server + LDAP outpost. Verified: all blueprints successful, outposts assigned, self-service recovery + passkeys active. Apply path for identity changes: redeploy this host (see `identity.md`).

## 7. nodTargets (agentless reconcilers)

`flake.nix → nodTargets` (all `targetType = "agentless"`; `nod` builds `#nodTargets.<name>.package` and runs its single binary locally):

| Target | Host | Package | Changes |
|---|---|---|---|
| `hom-rt-01` | 10.10.10.1 | `fritzbox-sync` | FRITZ!Box DNS / DHCP toggle / port forwards (TR-064) |
| `hom-ap-01` | 10.10.10.20 | `tplink-ap-sync` | RE330 SSID / bands |
| `hom-rly-01..08` | 10.10.30.11..18 | ESPHome device packages | Relay firmware/config (OTA) |
| `cloudflare` | api.cloudflare.com | `cloudflare-sync` | DNS records |

> **Resolved 2026-09-19:** the reconcilers (`fritzbox-sync`, `tplink-ap-sync`, the ESPHome sync
> scripts) now accept the deployment action as an optional positional argument, so
> `nod switch <target>` works. The Authentik target had the same defect and was removed. Verify
> `--dry-run` output before applying anything — both device reconcilers report a real diff now.

---

## 8. Emergency Recovery — Regaining Access

Order of attempts (stop as soon as one works):

1. **User account, key-based** — always available, no password involved:
   `ssh -i ~/.ssh/id_rsa philipp@173.249.22.211` (edge) · `…@37.114.55.91` (ops) · `…@10.10.10.10` (hom-srv-01).
   On the home server this is root already: `ssh -i ~/.ssh/id_rsa root@10.10.10.10`.
2. **Tailscale**: `tailscale status` on any reachable node; `ssh <user>@100.x.x.x`.
3. **WireGuard**: `ssh root@10.10.100.x` (only if peers handshake).

### 11.1 Which key does root trust? (verified 2026-09-20)

| Host | root trusts | Note |
|---|---|---|
| `hom-srv-01` | operator key (`WXfSlOz…`) + fleet key (`EduFlyo…`) | both verified by logging in as root |
| `cld-ops-01` | operator key + fleet key | the openclaw tunnel additionally logs in as root here, by design |
| `cld-edge-01` | operator key + fleet key | restored through the provider's rescue system; the old fleet key (`3zq1hFFw…`) is gone for good |
| `hom-wrk-01` | operator key + fleet key | local switch |

The **fleet deploy key** is `~/.ssh/nixfiles-deploy-key`, fingerprint
`SHA256:EduFlyoHwWJx3avw46lQsLksum5R0scm6z27OeqBeO4`, generated 2026-09-20 and authorised through
`my.features.system.networking.ssh.deployKeys` on every host. `~/.ssh/config`, `nod`'s
`identityFile` (`roles/base.nix`) and `deploy-rs`'s `-i` argument (`flake.nix`) all use it.

`~/.ssh/deploy-key` still points at the node tunnel secret
(`/run/secrets.d/2/infra/node_tunnel_key`) and must **not** be used to address the fleet. That path
is what destroyed the previous fleet key: a service credential rendered by a feature also granted
root on every host, and the feature's lifecycle overwrote it. The operator key stays authorised
everywhere as a fallback, and `~/.ssh/config` deliberately sets no `IdentitiesOnly`, so a mistake
here cannot lock the fleet out.

### 11.2 Recovering a lost account password

Needed when the declared hash and the host disagree, or when a password is not the intended one.
`root` itself is not an option: `PermitRootLogin = prohibit-password` and no root password is
declared, so root can log in neither over SSH nor at the console.

**Path 1 — the old password (no access to the host needed).** The password a host actually has is the
declared one, because servers set `users.mutableUsers = false` and re-apply it on every activation,
verified on `hom-wrk-01`. Candidates can be checked against a hash from history
without touching the VPS:
```bash
git show 513e176^:secrets/secrets.yaml > /tmp/old.yaml     # the state before the correction
sops -d /tmp/old.yaml | grep -A2 '^users:'                 # shows the hash (never the password)
# verify a candidate against that hash:
salt=$(sops -d /tmp/old.yaml | sed -n '/password:/{s/.*\$6\$//;s/\$.*//;p}')   # for a $6$ hash
openssl passwd -6 -salt "$salt" 'CANDIDATE'                # compare with the stored hash
# a self-test directly on the host also works:  ssh -t philipp@173.249.22.211 'sudo -v'
```

**Path 2 — GRUB over the provider console** (fastest; verified: GRUB has no password):
```
# provider panel → VNC/console, reboot
# at the GRUB menu press "e", append to the line starting with "linux":   init=/bin/sh
# then Ctrl-X to boot
mount -o remount,rw /
passwd philipp          # set the intended password
exec /sbin/init         # or: reboot -f
```

**Path 3 — provider rescue system.** Verified layout of `cld-edge-01`: `sda1` = ext4 = `/` (200 GB),
`sda15` = vfat = `/efi` (106 MB), BIOS boot:
```
mount /dev/sda1 /mnt
for d in dev proc sys; do mount --bind /$d /mnt/$d; done
chroot /mnt /bin/sh
passwd philipp
exit; umount -R /mnt; reboot
```

**After any manual password change, fix the declaration too.** With `mutableUsers = false` the next
activation writes the declared hash back, so a password set by hand on the host survives only until
the next deploy. The declaration in SOPS is the source of truth; the host is a copy of it.

**Afterwards, deploy the host once.** Servers declare `users.mutableUsers = false` and the secret
store now holds the correct hash, so the password is enforced from then on and cannot drift again.
That single activation also restores `ssh root@…` via the operator key, which unblocks the fleet key
rotation and the fleet-wide rollout (`practices.md` §4).
4. **Wired LAN** from a static-IP client: `ssh root@10.10.10.10` (hom-srv-01), FRITZ!Box UI `http://10.10.10.1`, AP UI `http://10.10.10.20`.
5. **Physical console** for home hardware.

If a bad NixOS config is suspected:
```bash
ssh root@<reachable> 'nixos-rebuild --rollback switch'      # live rollback
# or reboot and pick the previous generation in GRUB
```

If a **network service** was misconfigured:
- **DHCP gone:** statically configure a client, re-enable FRITZ!Box DHCP, disable Kea.
- **DNS gone:** client DNS → `1.1.1.1`; re-point FRITZ!Box DNS to `1.1.1.1`; fix Blocky.
- **FRITZ!Box unreachable:** LAN `10.10.10.1`; restore config export; factory reset only as last resort (ISP/PVC credentials required).
- **AP unreachable:** physical reset; re-run reconcile.
- **Complete network loss at home:** the FRITZ!Box is still the modem; its default LAN `10.10.10.1` remains the anchor.

> The **public IP on the cloud hosts is the ultimate lifeline** — it never depends on DHCP, DNS or the mesh of the home network.

---

## 9. Verification cheat-sheet

```bash
# per host
ssh root@<addr> 'systemctl --failed; readlink -f /run/current-system'

# contracts / services
ssh root@<addr> 'systemctl list-units --failed'

# DNS / DHCP (hom-srv-01)
ssh root@10.10.10.10 'dig +short @127.0.0.1 vyrx.de; journalctl -u kea-dhcp4-server -n 20'

# mesh
ssh root@173.249.22.211 'wg show'

# authentik (cld-edge-01)
curl -sk -o /dev/null -w '%{http_code}\n' https://auth.vyrx.de/
```

---

## 10. Known hazards

Standing conditions that will bite an operator who does not know them. Resolved items do not belong
here: they belong in the commit that resolved them.

| Hazard | Why it matters |
|---|---|
| Both agentless reconcilers reject the `switch` action argument | `nod switch hom-rt-01` / `hom-ap-01` may fail; run the tool directly |
| The FRITZ!Box's DHCP is **off** in the desired state | enabling Kea before reconciling the box gives you two DHCP servers on one segment, or none |
| Applying the `tplink-ap` reconciler unifies the SSIDs to `VYRX` on both bands and needs the access point at its current address | it changes the WLAN for everyone, including the microcontrollers that store the fleet SSID |
| The `tplink-ap` reconciler has never been run in apply mode | its desired state is verified as a **diff**, not as an applied state — the access point's SSID and band settings are still whatever the device already had. The `fritzbox` reconciler **has** been applied (2026-09-21): its diff is empty except the DHCP-announced DNS, which this box exposes no TR-064 action for |
| Authentik's `akadmin` is the only usable break-glass account | family accounts carry no password and are created through the enrollment flow |
| The remote forward-auth outpost is reached at an overlay address (`10.10.100.1:9055`) | Caddy logins on the LAN hosts break if the mesh is down |
| OpenClaw gateways require the ingress in `gateway.trustedProxies` | without it every proxy-shaped request is rejected |
| The resolver's blocklist refresh must not claim the resolver's directories | declaring `RuntimeDirectory`/`StateDirectory` = `knot-resolver` in `knot-blocklist.service` makes systemd re-own `/run/knot-resolver` and `/var/lib/knot-resolver` **as root**, which killed both resolvers twice on 2026-09-21 (`FileNotFoundError` on the manager's working directory, then `PermissionError` on its API socket). The refresh writes one file and reloads through systemd (`systemctl reload knot-resolver`, which runs as the user the resolver runs as). Any second caller of that directory breaks DNS for the whole house - and a `watchdog: true` on the RPZ is not an alternative, because the refresh replaces the file and the watchdog follows the inode |
| The box's IPv6 settings are **set by hand**, and no TR-064 action exists for them | a firmware update or a reset brings back router advertisements and DHCPv6, and with them a second resolver that answers our names with the public address - silently, because a device learns it over the segment, not through us. Check with a router solicitation (`rdisc6 -1 <iface>` on a LAN host: nobody must answer, measured 2026-09-21) |
| Nothing **forces** a device to use our resolver | DHCP offers only ours, the fleet hosts are configured for it, and the box no longer announces itself (no router advertisements, no DHCPv6). What remains is a device that is configured by hand to use `10.10.10.1`, or a hard-coded public resolver in a printer or TV - the segment is flat, so no rule of ours can stop it (see [architecture.md](architecture.md) §3.1). Outbound 53/853 to non-fleet destinations is not blocked, and DoH over 443 cannot be closed without breaking TLS; the real remedy is a second segment, not a firewall rule |
| A device keeps the resolver a network once taught it | measured 2026-09-21: a phone held the uplink router's address in its DNS list for hours after the router stopped announcing it, resolved one of our names through it, and got the *public* answer - the lookup looked like ours and was not. After any change to what is announced, reconnect the device and read its resolver list (`dumpsys connectivity` for Android, `resolvectl status` elsewhere); the audit's router-solicitation probe covers the announcing side, not the learned side |
| `nod switch` writes the boot entry but **advances no profile generation** | measured 2026-09-22: after many deploys, a reboot brought the hosts back on configurations from days earlier (Blocky instead of the resolver, iptables instead of nftables). The deployer runs `<closure>/bin/switch-to-configuration switch`, which installs the bootloader and writes an entry (`ssh_cli_deployer.rs`), but nothing in that path runs `nix-env -p /nix/var/nix/profiles/system --set <closure>` - the only `nix-env` calls are garbage collection. systemd-boot derives its `default` from the profile generation, so the entry for the new closure existed while the default kept pointing at the old one. `nixos-rebuild switch` does set the generation, which is why the same deploy behaves differently there. Until `nod` sets it, pin one by hand after a deploy: `nix-env -p /nix/var/nix/profiles/system --set <closure> && switch-to-configuration boot` |
| Nothing may write shell commands into the firewall | the whole policy is data, projected into the firewall's own rule options under the nftables implementation, which renders and applies one ruleset atomically. A command-shaped policy cost us the house's internet once (a syntax error stopped the firewall mid-reload and flushed the NAT of a zone) and left a withdrawn rule in the chain forever. The invariant `one firewall, rendered` and the `nftables-rules` check exist to keep it that way |

## 11. Appendix — Files, Secrets, Commands

**Key files**
- `flake.nix` — hosts, `deploy.nodes`, `nodTargets`.
- `features/system/networking/{gateway,fritzbox,tplink-ap,wireguard,static,topology}` — network model.
- `hosts/<host>/configuration.nix` — per-host feature switches.
- `features/services/authentik/**` — identity (see `identity.md`).
- `secrets/secrets.yaml` + `.sops.yaml` — encrypted secrets and age recipients.

**Relevant secrets**
`services/fritzbox/password`, `services/wifi/ap_password`, `infra.*_private_key`,
`services/authentik/core_env` (includes `AUTHENTIK_BOOTSTRAP_PASSWORD`),
`services/authentik/outposts/*-ldap-token`.

**Common commands**
```bash
git status && nix flake check
nixos-rebuild switch --flake .#<host> --target-host root@<addr>
nixos-rebuild switch --flake .#<host> --target-host root@<addr> --use-remote-sudo   # if needed
nod plan <host>            # preview
nod rollback <host>        # rollback
ssh root@<addr> 'nixos-rebuild --rollback switch'   # manual rollback
```

**Change history of this runbook:** created during the initial 2.0 rollout (cld-edge-01 first). Keep it updated as hosts are migrated.

### 13.1 `exit 4` from the Caddy reload - and what it actually was

`nixos-rebuild switch` returned `exit 4` on every activation of `hom-srv-01`, next to "Failed to reload
caddy.service". It is tempting to file that as a cosmetic quirk - systemd retrying a reload that the
end state does not depend on - and an earlier version of this section did exactly that. It was wrong:

- The reload **hung** once ("Reload operation timed out. Killing reload process.") while it had to
  load many newly bound `tls` files, and left Caddy listening but answering nothing. Every vhost on
  the host was down, from the LAN and through the ingress, until the service was restarted.
- The **loaded** unit carried an `ExecReload` pointing at `/etc/caddy/Caddyfile` while the service ran
  with `/etc/caddy/caddy_config`, so the reload failed on a path that no longer existed. A
  `systemctl daemon-reload` plus a restart rewrote the unit; activations now end with `exit 0` and log
  a successful reload.

What to keep: never classify a failing step as cosmetic because the end state looks fine. Read what
the failing unit **actually executed**, and compare it with what the service **actually runs with** -
the two had drifted apart here, and the mismatch was the whole story.
