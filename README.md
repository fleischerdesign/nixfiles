# NixOS Configuration (nixfiles 2.0 / VYRX Enterprise Architecture)

[![CI](https://github.com/fleischerdesign/nixfiles/actions/workflows/ci.yml/badge.svg)](https://github.com/fleischerdesign/nixfiles/actions/workflows/ci.yml)

Enterprise NixOS + Home Manager multi-node infrastructure managed via [Nix Flakes](https://nixos.wiki/wiki/Flakes), spanning 5 cluster hosts and embedded network hardware under the canonical domain `vyrx.de`.

## Cluster Inventory (RFC 1178 Enterprise Taxonomy)

| Host | Role | Subnet / Zone | Hardware | Purpose |
|------|------|---------------|----------|---------|
| `hom-wrk-01` | desktop | `10.10.20.10` (`corp`) | Intel PC / NVMe / Intel GPU | Workstation — Niri + Axis Shell, Sunshine, Gaming, OpenClaw Node |
| `mob-nb-01` | notebook | Roaming DHCP (`corp`) | AMD Laptop / NVMe | Daily Driver — Niri + Axis Shell, Codium, OpenClaw Node |
| `cld-edge-01` | server | `173.249.22.211` (`mesh`) | Cloud VPS (QEMU, GRUB) | Ingress Hub — WireGuard Hub, Caddy Edge, Authentik SSO, ntfy, DBs |
| `cld-ops-01` | server | `37.114.55.91` (`mesh`) | Cloud VPS (QEMU, GRUB) | Observability Master — Grafana, Prometheus, Loki, OpenClaw AI Gateway (`:18789`), Attic |
| `hom-srv-01` | server | `10.10.10.10` (`infra`) | Bare Metal (Intel, 4TB+1TB) | Core Gateway — Kea DHCP, Chrony NTP, Blocky DNS, \*arr stack, Jellyfin, Home Assistant, Klipper |

### Embedded Devices & Bridges
- `hom-rt-01` (`10.10.10.1`): AVM FRITZ!Box (Layer-1/2 Uplink Modem, DHCP/DNS offloaded to `hom-srv-01`).
- `hom-ap-01` (`10.10.10.20`): TP-Link RE330 Access Point (Layer-2 Wi-Fi bridge, SSIDs: `VYRX`, `VYRX-IOT`).

> **Naming:** host, service and zone names are specified normatively in [`NAMING.md`](NAMING.md)
> and derived — never maintained by hand. Public services are flat (`<service>.vyrx.de`),
> internal planes are `.lan` / `.mesh` / `.iot`, hosts live in the `node` plane
> (`<hostname>.node.vyrx.de`). The machine-generated list is `my.contracts.projections.fqdns`.

## Architecture Highlights

### 1. Service Contract Pattern & Storage Catalog (`my.contracts.provides`)
Services are completely decoupled and host-agnostic. Modules declare their endpoints, scopes, authentication policies, and persistent storage boundaries (`stateDirs`, `dataDirs`, `cacheDirs`). Multi-consumer projections automatically synthesize Caddy virtual hosts, firewall openings, and monitoring probes.

### 2. Stateless Kernel-WireGuard Mesh (`10.10.100.0/24`)
Zero external control planes (no Headscale, no Tailscale — retired 2026-09-20). Direct peer-to-peer ChaCha20-Poly1305 tunnels between all nodes with TCP-MSS clamping and anti-hairpinning routing. The same mesh delivers the home LAN zones to a roaming client, so nothing behind the LAN needs a second router or a public name.

### 3. Single-NIC Gateway & RFC 1812 Router-on-a-Stick
`hom-srv-01` acts as the single-NIC gateway for the home network, running Kea DHCPv4 (with static leases synthesized from `my.topology`), Chrony NTP, Blocky Split-Horizon DNS, and IPv4 packet forwarding.

### 4. Enterprise Identity & RBAC
Declarative Authentik blueprints provisioning users (**Philipp**, **Katja**, **Lilly**, **Kai**, **Rieke**) and groups (`infra-admins`, `media-users`, `family`) with FIDO2/Passkey support, LDAP outposts, and OIDC integrations.

### 5. Multi-Node AI Automation Mesh
Distributed OpenClaw agent mesh connected directly over WireGuard to the central gateway on `cld-ops-01:18789` with mutual A2A peering.

## Installation & Commands

```bash
# Clone repository
git clone https://github.com/fleischerdesign/nixfiles && cd nixfiles

# Dev shell (direnv auto-loads nixfmt, deadnix, statix, sops, nod, etc.)
direnv allow

# Activate pre-commit hooks
git config core.hooksPath .githooks

# Verify all hosts evaluate cleanly
nix flake check

# Build and switch locally
nixos-rebuild switch --flake .#<hostname>

# Deploy declaratively across the cluster
nod switch <hostname>

# Edit secrets
sops secrets/secrets.yaml
```
