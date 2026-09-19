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

### 3.2 Subnets (`my.topology.subnets`)

| Zone | CIDR | VLAN | Trust | Notes |
|---|---|---|---|---|
| `infra` | `10.10.10.0/24` | 10 | infra | Servers, FRITZ!Box, AP. Gateway via `10.10.10.1`. |
| `corp` | `10.10.20.0/24` | 20 | corp | Workstations. Gateway via `hom-srv-01` (`10.10.10.10`). |
| `iot` | `10.10.30.0/24` | 30 | iot | ESPHome / smart home. Gateway via `hom-srv-01`. |
| `mesh` | `10.10.100.0/24` | – | mesh | WireGuard overlay (IPv4). |
| `mesh-ipv6` | `fd10:1000:100::/64` | – | mesh | WireGuard overlay (RFC 4193 ULA). |
| `guest` | `10.10.99.0/24` | 99 | guest | Internet-only. |

### 3.3 Tailnet (transitional)

Tailnet owner `butchersmudda@`. **Node names are still the legacy musician names:**

| Tailnet node | Tailscale IP | Maps to (assumed) | State |
|---|---|---|---|
| `mackaye` | `100.120.39.68` | `cld-edge-01` | online |
| `rollins` | `100.126.5.72` | `cld-ops-01` | online (direct `37.114.55.91`) |
| `strummer` | `100.125.253.108` | `hom-wrk-01` | online |
| `yorke` | `100.107.168.30` | `hom-srv-01`? | offline |
| `jello` | `100.88.135.75` | `mob-nb-01`? | offline |

Verify before relying on the mapping: `ssh root@173.249.22.211 tailscale status`.

---

## 4. Connectivity & Transport Model

### 4.1 Transport priority

| Situation | Use |
|---|---|
| Cloud host, any time | **Public IP** (`root@<public-ip>`) — always-on lifeline |
| Transitional (now) | **Tailscale** (`root@100.x.x.x`) |
| Target (after rollout) | **WireGuard** (`root@10.10.100.x`) |

### 4.2 Why `nod switch` fails today

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

### 7.2 cld-ops-01
Public `37.114.55.91`, Tailscale `rollins` (`100.126.5.72`). Runs observability collector, Attic server, CrowdSec agent, OpenClaw gateway, Caddy.
```bash
nixos-rebuild switch --flake .#cld-ops-01 --target-host root@37.114.55.91
ssh root@37.114.55.91 'systemctl --failed'
```
Verify: Prometheus/Loki/Grafana reachable, Attic responds, OpenClaw gateway up.

### 7.3 hom-srv-01 — READ FIRST: §8 network cutover
LAN `10.10.10.10`. Runs media stack, Blocky (DNS), Kea (DHCP), Chrony, gateway/NAT, ESPhome, Home Assistant, Klipper, LDAP outpost, Tailscale subnet router (`10.10.0.0/16`).
Deploy over LAN (`root@10.10.10.10`) or Tailscale.
**Do not enable Kea DHCP before disabling FRITZ!Box DHCP (§8).**

### 7.4 hom-wrk-01
LAN `10.10.20.10`, Tailscale `strummer`. Desktop (Niri/Axis). Deploy over LAN/Tailscale; **verify graphically** (login, Wayland, Home Manager) — not automatable.

### 7.5 mob-nb-01
Roaming. Deploy when online (home LAN or Tailscale). Verify WireGuard roaming.

---

## 8. Network Cutover — FRITZ!Box ↔ hom-srv-01 (critical)

### 8.1 Current state (before cutover)

| Function | Provider |
|---|---|
| WAN uplink / modem | FRITZ!Box `10.10.10.1` |
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
This sets DNS to `10.10.10.10`, **disables FRITZ!Box DHCP**, and applies declarative port forwards.
```bash
# agentless reconciler (see §9 for the action-arg caveat — verify first!)
nod switch hom-rt-01 --dry-run     # preview
nod switch hom-rt-01               # apply (or run fritzbox-sync directly, §9)
```
Verify: FRITZ!Box UI reachable at `http://10.10.10.1`; a static-IP client still resolves DNS via `10.10.10.10`.

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

`tplink-ap-sync` reconciles **SSID (`VYRX`), 2.4 GHz and 5 GHz enable**. Changing the SSID **drops all Wi-Fi clients** until they reconnect.
- Management is over **wired** LAN (`10.10.10.20`) — keep wired access.
- If the AP becomes unreachable: physical reset button, rejoin, re-run the reconcile.
- Do this **after** §8.3 so DHCP/DNS are stable for reconnecting clients.

---

## 9. nodTargets (agentless reconcilers)

`flake.nix → nodTargets` (all `targetType = "agentless"`; `nod` builds `#nodTargets.<name>.package` and runs its single binary locally):

| Target | Host | Package | Changes |
|---|---|---|---|
| `hom-rt-01` | 10.10.10.1 | `fritzbox-sync` | FRITZ!Box DNS / DHCP toggle / port forwards (TR-064) |
| `hom-ap-01` | 10.10.10.20 | `tplink-ap-sync` | RE330 SSID / bands |
| `hom-rly-01..08` | 10.10.30.11..18 | ESPHome device packages | Relay firmware/config (OTA) |
| `cloudflare` | api.cloudflare.com | `cloudflare-sync` | DNS records |

> **Known issue (verify before relying on it):** `nod switch <agentless-target>` passes the deployment action (`switch`) as an argument to the reconciler binary. The current `fritzbox/sync.py` and `tplink-ap/sync.py` use `argparse.parse_args()` and have **no positional argument**, so they may abort with `unrecognized arguments: switch`. The Authentik target had exactly this defect and was removed.
> **Actions:** run `nod switch <target> --dry-run` first; if it errors, either
> (a) run the reconciler directly (`fritzbox-sync`, `tplink-ap-sync` — no action arg), or
> (b) fix the scripts to ignore/accept the action (e.g. `parse_known_args`).
> Treat this as a **blocker to fix** before the cutover is considered "wasserdicht".

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

1. **Public IP** (cloud hosts): `ssh -i ~/.ssh/deploy-key root@173.249.22.211` / `…@37.114.55.91`.
2. **Tailscale**: `tailscale status` on any reachable node; `ssh root@100.x.x.x`.
3. **WireGuard**: `ssh root@10.10.100.x` (only if peers handshake).
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

---

## 14. Appendix — Files, Secrets, Commands

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
