# VYRX 2.0 — Deployment & Network Cutover Runbook

> **Status:** Operational runbook (living document)
> **Audience:** Operators and autonomous agents. Everything needed to finish (or recover) the 2.0 rollout is here.
> **Companion docs:** `ARCHITECTURE.md` (target design), `PROVISIONING.md` (service config-as-code), `IDENTITY.md` (Authentik), `EMBEDDED.md` (IoT fleet), `AGENTS.md` (repo rules).
> **Emergency?** Jump straight to [§11 Emergency Recovery](#11-emergency-recovery--regaining-access).

---

## 1. Purpose

The 2.0 migration moves a historically grown setup ("hosts named after musicians", fragmented domains, `192.168.178.0/24`) onto:
- RFC 1178 host taxonomy and RFC 1918 zoning (`10.10.0.0/16`),
- declarative NixOS + Home Manager,
- a WireGuard mesh (`10.10.100.0/24`) as the target transport,
- **Tailscale as the transitional transport** until every host runs 2.0,
- `hom-srv-01` taking over LAN services (DHCP, DNS, NTP, gateway) from the FRITZ!Box.

This document is the **execution + safety guide**. It is deliberately explicit about **rollback and lockout avoidance**, because the rollout changes network services that can cut off the very access path you are deploying over.

---

## 2. Golden Rules (read before touching anything)

1. **Never remove your out-of-band path.** Before any network change you must have at least one working path that does *not* depend on the thing you are changing:
   - Public IP SSH (cloud hosts): `root@173.249.22.211`, `root@37.114.55.91`
   - Tailscale (`tailscaled` on most hosts)
   - Wired LAN access + a client with a **static IP** in the affected subnet
   - Physical console / keyboard for home hardware; LAN web UI for FRITZ!Box and RE330
2. **Keep Tailscale enabled** until WireGuard handshakes are verified on *all* hosts. It is the fallback mesh.
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

> **Target vs. reality:** this table lists the **2.0 target identity**. As of 2026-09-19 only `cld-edge-01` actually runs 2.0; the other hosts still have legacy hostnames and live on the old `192.168.178.0/24` LAN. See §3.3.

### 3.2 Subnets (`my.topology.subnets`)

| Zone | CIDR | VLAN | Trust | Notes |
|---|---|---|---|---|
| `infra` | `10.10.10.0/24` | 10 | infra | Servers, FRITZ!Box, AP. Gateway via `10.10.10.1`. |
| `corp` | `10.10.20.0/24` | 20 | corp | Workstations. Gateway via `hom-srv-01` (`10.10.10.10`). |
| `iot` | `10.10.30.0/24` | 30 | iot | ESPHome / smart home. Gateway via `hom-srv-01`. |
| `mesh` | `10.10.100.0/24` | – | mesh | WireGuard overlay (IPv4). |
| `mesh-ipv6` | `fd10:1000:100::/64` | – | mesh | WireGuard overlay (RFC 4193 ULA). |
| `guest` | `10.10.99.0/24` | 99 | guest | Internet-only. |

### 3.3 Tailnet (transitional) — VERIFIED 2026-09-19

Tailnet owner `butchersmudda@`. Tailscale node names are the **legacy musician names** and do **not** match the 2.0 hostnames yet. Verified by SSH (`hostname` / `ip addr`):

| Tailnet node | Tailscale IP | Actual `hostname` | Current address | 2.0 identity | State |
|---|---|---|---|---|---|
| `mackaye` | `100.120.39.68` | `cld-edge-01` | `173.249.22.211`, wg `10.10.100.1` | `cld-edge-01` — **migrated** | online |
| `rollins` | `100.126.5.72` | **`rollins`** (legacy) | `37.114.55.91` | `cld-ops-01` — not migrated | online |
| `strummer` | `100.125.253.108` | **`strummer`** (legacy) | `192.168.178.27` (old LAN) | `hom-srv-01` — not migrated | online |
| `jello` | `100.88.135.75` | **`jello`** (legacy, desktop) | `192.168.178.30` (old LAN) | admin workstation / `hom-wrk-01` — not migrated | online |
| `yorke` | `100.107.168.30` | unknown | – | likely `mob-nb-01` | offline (≥21h) |
| `m2007j3sg` | `100.79.228.38` | – | – | Android phone | online |

**Only `cld-edge-01` runs 2.0 today.** Every other host still runs the legacy configuration (legacy hostname, old `192.168.178.0/24` home LAN). Always confirm before targeting:
`ssh root@173.249.22.211 tailscale status`

---

## 4. Connectivity & Transport Model

### 4.1 Transport priority

| Situation | Use |
|---|---|
| Cloud host, any time | **Public IP** (`root@<public-ip>`) — always-on lifeline |
| Transitional (now) | **Tailscale** (`root@100.x.x.x`) |
| Target (after rollout) | **WireGuard** (`root@10.10.100.x`) |

### 4.2 Why `nod switch` / `deploy` fail today (both target the WG IP)

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

---

## 5. Pre-flight Checklist (every deploy session)

- [ ] `git status` clean; 2.0 changes committed (`git log --oneline -5`).
- [ ] `nix flake check` passes (eval all hosts + statix + deadnix).
- [ ] Required SOPS secrets present and decryptable on the target host:
      `services/authentik/*`, `services/fritzbox/password`, `services/wifi/ap_password`,
      `infra.*_private_key` (WireGuard), `services/cloudflare/*`.
- [ ] Backup done: FRITZ!Box config export (UI: System → Backup), current NixOS generation recorded
      (`readlink -f /run/current-system`).
- [ ] Out-of-band access confirmed for the target (public IP / Tailscale / wired LAN / console).
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
HOST=<host>; ADDR=<public-ip|tailscale-ip|lan-ip>

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
Identity/ingress host. Authentik server + LDAP outpost. Verified: all blueprints successful, outposts assigned, self-service recovery + passkeys active. Apply path for identity changes: redeploy this host (see `IDENTITY.md`).

**Naming/ingress rollout (2026-09-19): live.** The host now runs the flat public naming, the
cluster-wide ingress engine (vhosts + WireGuard upstreams), the `node` plane, the tunnel
credential and no apex catch-all. Verified: switch exit **0**, no failed units, 38 Cloudflare
records matching the projection, `auth`/`grafana`/`search`/`philipp.ai` 302, `cache`/`push` 200.

### 7.2 cld-ops-01 — DONE
Public `37.114.55.91`, Tailscale node still named `rollins` (`100.126.5.72`). Deployed 2026-09-19: hostname **`cld-ops-01`** (was `rollins`), generation `8siiv7vj…`, **0 failed units**. Runs observability collector, Attic server, CrowdSec agent, OpenClaw gateways (5), SearXNG, Caddy.
```bash
nixos-rebuild switch --flake .#cld-ops-01 --target-host root@37.114.55.91
ssh root@37.114.55.91 'hostnamectl --static; systemctl --failed'
```
Verified: `ops.vyrx.de` 200; `philipp|katja|lilly|kai|rieke.ai.vyrx.de` → 302 Authentik forward-auth; `ai.vyrx.de` → 301 → `philipp.ai.vyrx.de`; `search.vyrx.de` → 302; **wg0 up with a live handshake to `cld-edge-01` (`10.10.100.1`)**.
Open: `cache.ops.vyrx.de` has **no DNS record** (§13 #8); orphaned `/var/lib/docker` (§13 #9).

### 7.3 hom-srv-01 — READ FIRST: §8 network cutover
Currently **`strummer`** at `192.168.178.27` (old LAN), Tailscale `100.125.253.108`. Target: `10.10.10.10`. Runs media stack, Blocky (DNS), Kea (DHCP), Chrony, gateway/NAT, ESPhome, Home Assistant, Klipper, LDAP outpost, Tailscale subnet router (`10.10.0.0/16`).
Reach it today via Tailscale (`root@100.125.253.108`); `10.10.10.10` does not exist until the re-IP (§8.0).
**Do not enable Kea DHCP before disabling FRITZ!Box DHCP (§8).**

### 7.4 hom-wrk-01
Currently **`jello`** at `192.168.178.30` (old LAN, desktop), Tailscale `100.88.135.75`. Target: `10.10.20.10`. Deploy via LAN/Tailscale; **verify graphically** (login, Wayland, Home Manager) — not automatable.

### 7.5 mob-nb-01
Roaming; likely the offline Tailscale node `yorke` (`100.107.168.30`). Deploy when online. Verify WireGuard roaming.

---

## 8. Network Cutover — FRITZ!Box ↔ hom-srv-01 (critical)

### 8.0 Precondition — the home LAN is still on the OLD subnet

**Verified 2026-09-19:** the home LAN is still `192.168.178.0/24`; the FRITZ!Box is at `192.168.178.1` (HTTP 200); `hom-srv-01` (`strummer`) is `192.168.178.27`; the workstation (`jello`) is `192.168.178.30`. The 2.0 target is `10.10.10.0/24` with the FRITZ!Box at `10.10.10.1`.

This means the cutover is **not only a DHCP/DNS handoff — it is a full LAN re-IP**, including the FRITZ!Box. The declarative FRITZ!Box engine manages only **DNS / DHCP toggle / port forwards** — *not* the LAN IP. Moving the FRITZ!Box from `192.168.178.1` to `10.10.10.1/24` is therefore a **manual, high-risk step and an open design/execution item**; decide and document it before executing.

Conservative outline (to be agreed before execution):
1. Prepare a client that can hold a static IP in the **new** subnet (`10.10.10.x/24`) — this is the anchor during the re-IP.
2. Re-IP the FRITZ!Box LAN to `10.10.10.1/24` (DHCP still on) in the maintenance window; reconnect the anchor client and confirm WAN + management.
3. Bring up `hom-srv-01` as `10.10.10.10` and follow §8.3 for the DHCP/DNS handoff.
4. **Rollback:** set the FRITZ!Box LAN back to `192.168.178.1/24`; the anchor client keeps working.

### 8.1 Current state (before cutover)

| Function | Provider |
|---|---|
| WAN uplink / modem | FRITZ!Box `192.168.178.1` (target `10.10.10.1`) |
| DHCP (all LAN subnets) | FRITZ!Box |
| DNS (handed to clients) | FRITZ!Box |
| Routing infra → WAN | FRITZ!Box |

### 8.2 Target state (after cutover, per `my.topology` + feature code)

| Function | Provider |
|---|---|
| WAN uplink / modem | FRITZ!Box `10.10.10.1` (unchanged) |
| DHCP | **`hom-srv-01` Kea** (`enp2s0`); FRITZ!Box DHCP **off** |
| DNS handed out | **`10.10.10.10` (Blocky)** primary, `1.1.1.1` fallback |
| Routing corp/iot → WAN | `hom-srv-01` (`ip_forward` + `MASQUERADE`) |
| NTP | `hom-srv-01` Chrony (`allow 10.10.0.0/16`) |

Kea subnets: `10.10.10.0/24` pool `.100–.200` (router `10.10.10.1`), `10.10.20.0/24` and `10.10.30.0/24` pools `.100–.200` (router `10.10.10.10`), plus static reservations from topology MACs.

### 8.3 Safe staged sequence

> Do **one step at a time**, verify, and only then proceed. Between steps you can always roll back (§8.4).

**Step 1 — Deploy hom-srv-01 with DHCP OFF (avoid dual-DHCP).**
Temporarily set in `hosts/hom-srv-01/configuration.nix`:
```nix
my.features.system.networking.gateway.enableDhcp = false;
```
Deploy. Verify routing/NTP/Blocky:
```bash
ssh root@10.10.10.10 'systemctl status blocky chrony; dig +short @10.10.10.10 vyrx.de; chronyc clients'
```

**Step 2 — Verify Blocky answers before touching FRITZ!Box DNS.**
`dig @10.10.10.10` must resolve. If not, stop and fix Blocky.

**Step 3 — Reconcile the FRITZ!Box.**
The reconciler is implemented (`features/system/networking/fritzbox/sync.py`); `nod` still fails (§4.2),
so run the built binary directly — `--dry-run` prints a real per-item diff:
```bash
P=$(nix build --no-link --print-out-paths .#nixosConfigurations.hom-srv-01.config.my.features.system.networking.fritzbox.package)
$P/bin/fritzbox-sync --dry-run     # read-only preview
$P/bin/fritzbox-sync              # apply
```
It manages the **LAN address / subnet mask** (`SetIPInterface`), the **DHCP range**
(`SetAddressRange`) and **DHCP on/off** (`SetDHCPServerEnable`), and removes **port forwardings**
(the declared target is Zero Open Ports).

Two things it cannot do, both verified on the device:
- **The DHCP-announced DNS cannot be set over TR-064** (`LANHostConfigManagement:1` exposes no
  such action, and no other of its 46 services does either). Set `10.10.10.10` in the box UI, or
  ignore it — once Kea serves DHCP the box no longer announces DNS at all.
- **The LAN address change is a hard cutover** (see §8.6).

**Before applying, confirm this diff:** the box currently forwards **TCP/80 and TCP/443 to
`192.168.178.27`** (legacy bypass of the edge ingress). The reconciler will **delete** them —
intended, but it is an externally visible security change.

Verify: FRITZ!Box UI reachable at `http://10.10.10.1`; a client still resolves via `10.10.10.10`.

**Step 4 — Bring Kea up.**
Revert the temporary change (`gateway.enableDhcp = true`) and redeploy hom-srv-01.
```bash
nixos-rebuild switch --flake .#hom-srv-01 --target-host root@10.10.10.10
ssh root@10.10.10.10 'systemctl status kea-dhcp4-server; journalctl -u kea-dhcp4-server -n 30'
```

**Step 5 — Verify a test client.**
Force a client to re-lease (`dhclient -r && dhclient` or reconnect). It must receive an address in the zone pool with the correct router/DNS. Check both an `infra` and a `corp`/`iot` client if possible.

### 8.4 Rollback per step

| Failure | Action |
|---|---|
| Blocky not resolving | Leave FRITZ!Box DNS unchanged; fix Blocky; do not proceed. |
| Clients lose DHCP after Step 4 | Re-enable FRITZ!Box DHCP (`settings.dhcp.enable = true` → reconcile), disable Kea (`enableDhcp = false`), redeploy. |
| DNS broken network-wide | Set a client to `1.1.1.1` manually; re-point FRITZ!Box DNS to `1.1.1.1`; fix Blocky. |
| Lost FRITZ!Box management | Access via LAN `10.10.10.1` / restore config export / factory reset (needs ISP credentials). |
| hom-srv-01 broken | Boot previous generation (GRUB) or `nixos-rebuild --rollback switch` over LAN/Tailscale. |

### 8.5 AP cutover (TP-Link RE330, `hom-ap-01` / `10.10.10.20`)

**The reconciler cannot change the SSID.** The library exposes only `set_wifi(wifi, enable)` for
the RE330 — it toggles a band and nothing else (`ssid`/`psk` setters exist for other models, not
this one). `tplink-ap-sync` therefore owns **band enablement** and reports the SSID as a diff.

Renaming `Ancoris` → `VYRX` is a **one-time UI action** on the AP (done while someone is home),
and it must happen **before** the FRITZ!Box moves (§8.6): afterwards the AP still bridges Wi-Fi to
LAN, but its management address is on the dead old subnet until it re-leases.
- Management is over **wired** LAN — keep wired access.
- If the AP becomes unreachable: physical reset button, rejoin, re-run the reconcile.
- Renaming drops every Wi-Fi client once; they reconnect to the same AP, so it self-heals.

### 8.6 The one unavoidable disruption — and the correct phase order

Moving the box's LAN address invalidates every existing lease: clients still hold
`192.168.178.x/24` with gateway `192.168.178.1`, which no longer exists. Same-subnet traffic
(a legacy-address host such as `hom-srv-01`, see `migration.addresses`) keeps working, but
**gateway and internet do not** until each client renews. There is no way around one renewal per
device (the box cannot serve two subnets); it is a single disruption, not a recurring one:

| Step | Effect on clients |
|---|---|
| Box moves to `10.10.10.1`, still serving DHCP with range `10.10.10.20-.99` | one lease renewal, then gateway/DNS are correct again |
| Kea takes over DHCP (box DHCP off) | **none** — same subnet, same gateway, same DNS |

Practical mitigation: announce it, do it when the house is quiet, and toggle Wi-Fi on any device
that clings to its old lease. A short lease time on the box (UI setting) makes renewals come
faster.

**Corrected order** (the device layer must be handled while the old subnet still routes):

1. **Relays first** (§P6): flash with **both** SSIDs (`VYRX` + `Ancoris`) while they are still
   reachable on `192.168.178.x`. Keep them on **DHCP** in this first flash — a static `10.10.30.x`
   address would make them unreachable until Kea serves the `iot` subnet; move them to static
   addresses only after the cutover.
2. **Then the AP rename** (one click, §8.5) — the relays already follow both SSIDs, so nothing
   is locked out.
3. **Then the box** (Step 3) and **Kea** (Step 4).

---

## 9. nodTargets (agentless reconcilers)

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

## 10. WireGuard ↔ Tailscale Transition

- WireGuard is **already configured** on the servers (`wg0` up on `cld-edge-01`; relay hubs = `cld-edge-01` + `cld-ops-01`). Spokes use the primary hub for the full mesh CIDR.
- Peers currently do **not** handshake (`wg show` shows `0 B received` for spokes) because the other hosts are not on 2.0 yet.
- **As each host is deployed, its WG peer comes up.** Verify:
  ```bash
  ssh root@173.249.22.211 'wg show wg0; wg show wg0 latest-handshakes'
  ```
- **Cutover criteria (only then switch transport to WG and retire Tailscale):**
  1. All 5 cluster hosts deployed on 2.0.
  2. Handshakes present for every spoke on both relay hubs.
  3. `10.10.100.x` reachable from the admin workstation.
  4. `deploy.nodes.<host>.hostname` verified to resolve to reachable WG addresses.
- Until then: **keep Tailscale enabled** on every host.

---

## 11. Emergency Recovery — Regaining Access

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
rotation and the fleet-wide rollout (`QUALITY.md` §5).
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

> The **public IP on the cloud hosts is the ultimate lifeline** — it never depends on DHCP/DNS/WG/Tailscale of the home network.

---

## 12. Verification Cheat-Sheet

```bash
# per host
ssh root@<addr> 'systemctl --failed; readlink -f /run/current-system'

# contracts / services
ssh root@<addr> 'systemctl list-units --failed'

# DNS / DHCP (hom-srv-01)
ssh root@10.10.10.10 'dig +short @127.0.0.1 vyrx.de; journalctl -u kea-dhcp4-server -n 20'

# mesh
ssh root@173.249.22.211 'wg show; tailscale status'

# authentik (cld-edge-01)
curl -sk -o /dev/null -w '%{http_code}\n' https://auth.vyrx.de/
```

---

## 13. Known Gotchas / Open Items

| # | Item | Impact | Action |
|---|---|---|---|
| 1 | `nod` targets WireGuard IPs only (`tailscaleIp` shim = `wireguardIpv4`) | `nod switch` fails until WG peers up | Use `nixos-rebuild --target-host` now; fix mapping later (§4.2) |
| 2 | Agentless reconcilers reject the `switch` action arg | `nod switch hom-rt-01` / `hom-ap-01` may fail | Verify `--dry-run`; fix scripts (§9) |
| 3 | Authentik remote forward-auth → embedded outpost `10.10.100.1:9055` | Remote Caddy login breaks if WG down | Deploy host over LAN/Tailscale; verify WG up after deploy |
| 4 | FRITZ!Box DHCP default is **off** in desired state | Enabling Kea before reconciling → dual DHCP or no DHCP | Follow staged §8.3 |
| 5 | Tailnet still uses legacy musician node names | Wrong host assumption | `tailscale status` before targeting (§3.3) |
| 6 | `rm -rf /var/lib/authentik` | Authentik service CHDIR failure | Fixed via tmpfiles rule; recreate dir if manual wipe |
| 7 | Authentik `akadmin` is the only usable break-glass account | Family accounts have no password | Log in as `akadmin`; set/`Passwort vergessen` |
| 8 | ~~Attic had no Cloudflare DNS record~~ **fixed.** The flat name is `cache.vyrx.de`, projected from the Attic contract endpoint; the ad-hoc `*.ops` wildcard is obsolete (#10). | — |
| 9 | Legacy `/var/lib/docker` (21 GB, `camofox`) orphaned on `cld-ops-01` | Wasted disk; `camofox` is not referenced in the repo anymore | `rm -rf /var/lib/docker` once nothing needs it |
| 10 | ~~Cloudflare held the removed wildcards~~ **closed.** `*.vyrx.de`, `*.ai.vyrx.de`, `*.ops.vyrx.de`, the stale `search.vyrx.de` CNAME and the wrongly created `fleischer.design.vyrx.de` were deleted; the live zone now equals the projection (38 records, internal planes absent). | — |
| 12 | ~~`sandbox.<name>.ai.vyrx.de` had no listener~~ **closed.** Root cause: `mcp.apps.enabled` was never set, so OpenClaw never started its sandbox-only listener (the `port + 100` override is correct and configurable — `port + 1` would collide with the packed gateway ports). Fixed and verified: 18889–18894 listen, `/mcp-app-sandbox` is 200 through the ingress, `/` is 404 by design. | — |
| 13 | OpenClaw gateways require the ingress in `gateway.trustedProxies`; without it every proxy-shaped request is rejected with `proxy_attribution_required` | Broken public routes | Derived from `my.topology.ingressHost` in the gateway feature; the ingress also overwrites `X-Forwarded-For/-Proto/-Host` (fix in place — do not regress either half) |
| 11 | Naming model changed: flat public names, ingress engine, Blocky split horizon, `node` plane | Deploy order matters — DNS/TLS must exist before a name is served | Deploy `cld-edge-01` first, then `cld-ops-01`, `hom-srv-01`, clients. See `NAMING.md` §9/§12 |
| 14 | Migration scaffolding (host `migration` block, watchdog, legacy labels) is temporary by design | Left in place the repository describes two states at once and an obsolete path onto the host stays open | Run the teardown in §14; `my.contracts.projections.migrationDebt` reports what is still temporary |
| 15 | Running the FRITZ!Box reconciler in **apply** mode **is** P3 | It disables the box DHCP and hands out DNS `10.10.10.10`, which only exists after P1 (hom-srv-01 deployed). Applied too early it breaks DHCP/DNS for the whole LAN | Never apply before P1. Verify read-only with `…fritzbox.package/bin/fritzbox-sync --dry-run` (needs a TR-064 user: FRITZ!OS ≥ 7.24 rejects the password-only login, `dslf-config` is gone) |
| 16 | Applying the `tplink-ap` reconciler **unifies the SSIDs to `VYRX`** (2.4 + 5 GHz) and needs the AP at its target address | Wi-Fi clients reconnect / lose a separate SSID | AP last (P5). Verify read-only with `…tplink-ap.package/bin/tplink-ap-sync --dry-run`; both reconcilers are dry-run-verified against the live devices |
| 17 | `srv.lan.vyrx.de` is a host-specific **public** record, updated by `hom-srv-01` itself via `cloudflare-dyndns` to the home's dynamic address — while `NAMING.md` §1.1 cites exactly this name as an anti-example, and the spec has no rule for a host's dynamic public address | two naming schemes describe the same host: `srv.lan.vyrx.de` (public, dynamic) and `hom-srv-01.node.vyrx.de` (the node plane, which carries the overlay address, not the public one). Nothing internal uses the former — Blocky resolves it to the ingress regardless | decide once, in the spec: either drop the dyndns entry (measured: the public record points at `93.219.137.122`, the home's uplink) or add a public-plane rule for a dynamic host address. The Cloudflare reconciler deliberately does **not** own this record (it carries no engine comment), so `--prune` will never touch it |

---

## 14. Migration Scaffolding — Teardown Checklist

Every transitional artifact is **deprecation debt with an expiry**. The repository must end up
describing exactly one state (the target): scaffolding that lingers keeps an obsolete address
and default route alive, is a second forgotten path onto the host, and will collide with the
very networks we migrated for. `my.contracts.projections.migrationDebt` reports what is still
temporary — a **report, never an assertion**, because an assertion would block the migration it
is meant to clean up after.

### 14.1 Gate — do not start until all of these hold

- [ ] every client holds a lease from `10.10.10.0/24` (Kea leases/logs, not the FRITZ!Box)
- [ ] the FRITZ!Box answers on `10.10.10.1` and its DHCP is off
- [ ] `grep -rn '192\.168\.178' --include='*.nix' .` returns **no** hits (documents may keep history)
- [ ] `ip -4 neigh` on `hom-srv-01` shows no neighbour in the old subnet
- [ ] a stability window has passed (days, not hours) before the rollback generations are pruned

### 14.2 Teardown steps (each independently reversible)

| # | Change | Verification |
|---|---|---|
| 1 | empty `my.topology.hosts.hom-srv-01.migration` (`addresses = []`, `gateway = null`), redeploy | `ip -br a` shows only `10.10.10.10`; default route via `10.10.10.1`; Tailscale and services up |
| 2 | remove the migration watchdog (unit + timer + file) | deploy is clean, no unit left |
| 3 | drop the reconciler's old-address input and `hom-rt-01.migration` | a reconciler run reports "unchanged" |
| 4 | delete the `migration` option from the topology schema once no host needs it | `nix flake check`, `nix fmt`, statix/deadnix clean |
| 5 | remove rename leftovers one by one (e.g. `ntfy.vyrx.de`); `fleischer.design`, `*.pub.*` and `docs.lan.vyrx.de` are **intended** aliases | the alias report shrinks to the intended set |
| 6 | remove the legacy topology shim once nothing reads it | `grep -rn 'networking\.topology' features/ roles/` |

### 14.3 What stays (target state, not scaffolding)

`my.topology.hosts.<h>.interface`, `my.topology.resolvers`, the router reconciler's
LAN/DHCP/DNS/forward capability, `enableDhcp`, and the naming invariants I1–I11.

---

## 15. Appendix — Files, Secrets, Commands

**Key files**
- `flake.nix` — hosts, `deploy.nodes`, `nodTargets`.
- `features/system/networking/{gateway,fritzbox,tplink-ap,wireguard,tailscale,static,topology}` — network model.
- `hosts/<host>/configuration.nix` — per-host feature switches.
- `features/services/authentik/**` — identity (see `IDENTITY.md`).
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
