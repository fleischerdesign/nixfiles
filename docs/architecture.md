# Architecture

> **Domain:** `vyrx.de` · **Overlay:** WireGuard `10.10.100.0/24`, `fd10:1000:100::/64` ·
> **LAN supernet:** `10.10.0.0/16`

This is the specification of the system as it is. It defines the vocabulary the other documents use -
host, zone, plane, contract - and the rules that connect them. Where a statement is enforced, the
invariant that enforces it is named; where it is measured, the command that measures it is.

## 1. Principles

1. **Services, not machines.** A service owns a DNS name; which host runs it is a deployment decision
   that may change without a consumer noticing. Names are derived from contracts (§6), never written.
2. **Deterministic host names (RFC 1178).** `<location>-<role>-<index>`: `hom-srv-01`, `cld-edge-01`.
3. **One name, one answer per plane.** A public name resolves to the ingress from outside and to the
   LAN host from inside - split horizon, not two names.
4. **Collision-free addressing.** `10.10.0.0/16` behind `10.10.100.0/24`, so a roaming client can
   never collide with the network it happens to be attached to.
5. **The inventory decides.** Addresses, zones, names, firewall rules and DNS records are functions
   of `my.topology` and the contract projections. Writing one twice means a derivation is missing.
6. **Self-hosted identity, no external control plane.** Authentik, ntfy and the WireGuard mesh replace
   SaaS identity, push and connectivity; no vendor sits in the data path.
7. **Evidence over intention.** Every claim here is either asserted by a check in this repository or
   measured by a named command.

## 2. Hosts

| Host | Role | Zone | Address | Mesh | Runs |
|---|---|---|---|---|---|
| `cld-edge-01` | server | `mesh` + public | `173.249.22.211` | `10.10.100.1` | Ingress (Caddy), Authentik core, CrowdSec master, observability stack, primary database, ntfy |
| `cld-ops-01` | server | `mesh` + public | `37.114.55.91` | `10.10.100.2` | Observability collector, Attic binary cache, CrowdSec agent |
| `hom-srv-01` | server | `infra` | `10.10.10.10` | `10.10.100.10` | LAN gateway (DHCP, DNS, NTP, NAT), media stack, Home Assistant, Klipper, local ingress, ESPHome flashing |
| `hom-wrk-01` | desktop | `corp` | `10.10.20.10` | `10.10.100.20` | GNOME desktop, development environment |
| `mob-nb-01` | notebook | `corp` (roaming) | DHCP | `10.10.100.30` | GNOME notebook; reaches the LAN over the mesh |

The table is illustrative; the declaration is [`inventory/hosts.nix`](../inventory/hosts.nix), and the
per-host service list follows from the contracts each host enables. Devices that cannot run NixOS but
belong to the LAN (printers, relays, access points) are declared in `my.topology.devices` and
reconciled agentlessly - see [embedded.md](embedded.md). A device that cannot run NixOS but needs the
**mesh** (a phone, a tablet) is not a LAN device: it has no `ipv4`, only an overlay identity, and is a
`my.topology.hosts` entry with `hostType = "client"`, its WireGuard configuration rendered as a
wg-quick file (`my.features.system.networking.wireguard.clientConfigs`).

## 3. Network model

### 3.1 One Layer-2 segment, five zones

The house is one flat Layer-2 segment. Zones are addressing and policy, not separate broadcast
domains: a zone is a subnet with a trust level, plus the firewall rules that treat it. There are no
VLANs - a second segment needs hardware that does not exist yet, and the model is honest about that
instead of implying isolation that nobody implemented.

| Zone | CIDR | Gateway | Trust | Contains |
|---|---|---|---|---|
| `infra` | `10.10.10.0/24` | `10.10.10.1` | highest | `hom-srv-01`, access point, router |
| `corp` | `10.10.20.0/24` | `10.10.20.1` | trusted | workstations, phones, roaming clients |
| `iot` | `10.10.30.0/24` | `10.10.30.1` | isolated | printer, relays, 3D printer |
| `guest` | `10.10.99.0/24` | `10.10.99.1` | untrusted | guests, internet only |
| `mesh` | `10.10.100.0/24` | `10.10.100.1` | trusted transport | the overlay itself |

The authoritative declaration is [`inventory/subnets.nix`](../inventory/subnets.nix); an unknown zone
fails the build. Because the segment is flat, everything on it can be asked directly, not only reached
through the gateway - which is why isolation is a firewall property (§3.4), not a segment property.

### 3.2 DHCP: the inventory decides the zone

`hom-srv-01` runs Kea. All served subnets sit in one shared network, because Kea selects a subnet for a
directly connected client by the receiving interface address and ignores classification:

- one class per served zone, matched on the MAC addresses its inventory entries declare;
- the default zone (`corp`) carries the complement class, because a subnet that names no class accepts
  every client;
- `guest` is deliberately not served by this gateway.

A device that is not in the inventory gets a default-zone lease. That is the rule, not a fallback.

### 3.3 The gateway

`hom-srv-01` is a single-NIC router-on-a-stick (RFC 1812): default router, DHCP server, resolver, NTP
server and NAT for the trusted zones. The uplink is `hom-rt-01` at `10.10.10.1`, a transparent modem -
no DHCP, no DNS handed to clients, no port forwardings. The zone gateways are addresses on the one
interface; which zones a host serves follows from its role, because a zone gateway must live inside the
zone to be installable as a default route.

IPv6 is deliberately absent from the LAN: Kea DHCPv4, no DHCPv6, no router advertisements, no IPv6
prefix in any zone. The only IPv6 in the fleet is the ULA of the mesh (§4).

### 3.4 Isolation

Isolation is the firewall and the trust model, not segments:

- forwarding is enabled per zone and only where the trust level permits; `iot` and `guest` never
  transit;
- NAT carries the trusted zones only;
- the IoT zone may answer requests from `hom-srv-01` (Home Assistant, Klipper) and reach the internet,
  and nothing else.

## 4. The mesh

Kernel WireGuard, derived from `my.topology`. No control plane, no database, no vendor.

```
        cld-edge-01 10.10.100.1  <------>  cld-ops-01 10.10.100.2      both public, both relays
              ^                                    ^
              |  dual-homed spokes, keepalive 25   |
      +-------+--------+---------------+-----------+
  hom-srv-01      hom-wrk-01       mob-nb-01                     the LAN is behind hom-srv-01
  10.10.100.10    10.10.100.20     10.10.100.30
```

- **Dual hub.** Every host peers with both cloud hosts; the primary carries the overlay CIDR for
  transit, the secondary is reached by its own `/32`, so a hub can be taken out without touching a
  spoke.
- **Longest-prefix cryptokey routing.** A peer carries its overlay address plus whatever it announces;
  at most one host may deliver a zone, and every delivered zone is a `/24`.
- **A zone is carried when it holds a device that cannot speak for itself.** A printer, relay or
  microcontroller has one address and no overlay identity, so a node outside the LAN reaches it only
  when its zone is routed. A host zone is never carried: its hosts answer at their overlay address.
  `my.topology.lanRouter` names the carrier, `my.topology.announcedZones` what it carries.
- **What the mesh carries, it carries as an allow-list.** `my.topology.devices.<name>.endpoints` names
  a port and the trust levels that may use it; the carrier forwards exactly that. A blanket accept for
  the mesh would make the routing decision and the permission decision one decision.
- **One firewall, and it is rendered, not written.** What the mesh carries, what an endpoint exposes
  and which zones may reach the uplink are data, projected into the firewall rule options under the
  nftables implementation, which renders one ruleset atomically. Both chain policies are `drop`, so
  what nobody declared is closed by construction.
- **The mesh is the last resort.** Route metric 1000 against NetworkManager at 600, so a directly
  reachable prefix always wins and a client at home does not send LAN traffic through the cloud.
- **IPv6 by design.** Alongside `10.10.100.0/24` the mesh spans `fd10:1000:100::/64` (RFC 4193 ULA).
- **MSS clamping** in both directions, so TCP handshakes survive mobile uplinks.

These promises are held by `checks.network-invariants` (part of `nix flake check`) against the evaluated
fleet, and measured against the running fleet by `nix run .#network-audit`.

## 5. Names, DNS and certificates

### 5.1 Planes, and how a name is derived

Names are derived, not maintained. An FQDN is a function of the topology and the contract projections,
which is what makes a host rename a derivation change rather than a migration with a checklist. The
rules are enforced at evaluation time in [`contracts/naming`](../contracts/naming/nixos.nix).

| Plane | `scope` | Suffix | Published | Reached via |
|---|---|---|---|---|
| public | `"public"` | `vyrx.de` (apex) | Cloudflare | ingress host (reverse proxy) |
| lan | `"internal"` | `lan.vyrx.de` | no | home LAN |
| mesh | `"mesh"` | `mesh.vyrx.de` | no | WireGuard mesh |
| node | `"isolated"` has no name; host and device plane | `node.vyrx.de` | Cloudflare | overlay address, admin only |
| isolated | `"isolated"` | - | no | direct address and port only |

```
fqdn(endpoint)     = "${subdomain}.${planeSuffix(scope)}"   # null when scope = "isolated" or no subdomain
hostFqdn(host)     = "${hostname}.node.${domain}"           # cld-edge-01.node.vyrx.de
deviceFqdn(device) = "${name}.node.${domain}"               # hom-prn-01.node.vyrx.de
```

The suffix is the only thing that encodes visibility and it never encodes a host. `scope` is the
contract enum (`public | internal | mesh | isolated`, default `internal`); it maps to the suffix, so
the name never depends on placement. `iot` is not an endpoint scope - IoT names come from the device
inventory and use the `node` plane. A device in a carried zone is answered on the `node` plane with its
one address; a device whose zone is not carried is answered only on the LAN.

An alias is a CNAME to the derived FQDN in the same plane, projected identically by every engine, so a
rename is additive and reversible. Invariants I1-I9 (unique derived hostnames, no host label in a
service name, no internal plane in the public zone, an unauthenticated public endpoint must declare
`publicExempt`, and so on) fail the build. Read-only projections for inspection:
`my.contracts.projections.{fqdns,hostFqdns,dnsRecords,ingressVhosts}`.

### 5.2 Split horizon

The resolvers (`features/services/dns`, Knot Resolver 6) answer three planes and choose by the source
address and the door the query arrived at, so one name has one address per plane:

| Plane | Source | Resolves to |
|---|---|---|
| `lan` | a home zone | the LAN address, so the packet stays local |
| `overlay` | the mesh | the overlay address, reachable over `wg0` |
| `public` | anything else | the ingress for a public service, the overlay for a node |

A device has no overlay identity, so the `lan` plane answers its only address; the `overlay` plane
answers it only when its zone is carried, because a name that resolves to an address nothing routes
would be worse than no answer. The same resolver serves both doors: a client at home asks over the LAN,
a client away from home asks over DNS-over-TLS at the public door, where the ingress terminates the
resolver name and certificate. A client therefore configures one name and is answered by the door its
network can reach.

Resolution is not a single point of failure: `my.topology.resolverHosts` declares who serves DNS, and
each generates the same zones from the same inventory. A host resolves through doors derived by
`features/system/networking/resolver`: a host with its own address in a home zone has the home door
alone, a roaming home-zone client tries the home door first and then the mesh doors. `FallbackDNS` is
empty and the global routing domain is `~.`, so DHCP-provided resolvers never enter the path.

### 5.3 Certificates: one per name, issued where it terminates

There is no fleet wildcard: Cloudflare Universal SSL owns the apex wildcard and `_acme-challenge` is
not ours to write. Each name is issued on the host that terminates it, so no key material is copied.
The ingress validates with HTTP-01 (the names resolve to it); hosts behind split horizon use DNS-01 via
the Cloudflare API with the credential as a systemd credential; names outside the public zone fall back
to `tls internal`. Internal `.lan` names get public certificates too, so they appear in certificate
transparency logs - a deliberate trade-off.

### 5.4 Which address a service uses

A service uses an address the far side can actually reach
(`contracts/topology/lib/service-address.nix`): the LAN address while both sides are in a home zone,
the overlay address otherwise. That one rule replaced five modules that each decided for themselves. A
rendered wg-quick client is told the mesh resolvers as `DNS =`, which is what makes its VPN network
able to resolve our names at all.

## 6. Service contracts

A service declares what it offers and what it needs; the platform derives the rest. No service module
knows its host, its name or its neighbours.

| Declaration | Meaning | Projected to |
|---|---|---|
| `my.contracts.provides.<svc>.endpoints` | listeners: port, transport and application protocol, direct access | firewall rules, telemetry targets, ingress upstreams |
| `...publications.<name>` | a name on a listener: DNS identity, exposure plane, ingress policy, audience | DNS records, Caddy vHosts, mesh reachability, access policies |
| `...identity.oidc.<name>` / `...identity.ldap.<name>` | application integrations referencing a publication | Authentik blueprints, directory consumers |
| `...presentation.tiles` / `.readouts` / `.actions` | portal entries referencing an endpoint | portal inventory and adapter data |
| `...telemetry.probes` / `.scrapes` | named probes and scrapes referencing an endpoint | Prometheus jobs, portal monitoring state |
| `...storage`, `...backup` | persistence needs and what must be restorable | storage contracts, backup sets, adapter jobs |
| `...dependsOn` | fleet-wide service references, validated per host | portal dependencies |
| `my.contracts.consumes.<svc>.postgresql.<db>` / `.ldap` | a database and user, or a directory identity | provider resources, declared by the provider engine |
| `my.desktop.environments`, `.effects`, `.surfaceOpacity` | session, layer surfaces and window effects | compositor layer and window rules (account scope) |

Each domain owns its schema; references between domains are validated at evaluation, so an unknown
endpoint, a nameless publication, an ingress on a non-HTTP listener, authentication without an ingress
or a duplicate Prometheus job name fails the build with a named offender. An account-scope domain
carries a `home.nix` half beside its `nixos.nix`; the system builder attaches those through
`home-manager.sharedModules` and leaves them out where that module is absent.

Consequences worth knowing: a `public` publication gets its name, certificate and proxy rather than
asking for them; services never reference a host, so moving one is a one-line change in `hosts/`; and a
path exempted from authentication is proxied without `forward_auth`, so it carries no identity headers -
a page that reads identity must never be exempted, and `checks/vyrx-portal.nix` holds the exempted set
equal to the set the application declares public.

Caddy disables TLS 0-RTT on its HTTP/3 listeners. Forwarded client attribution requires a verified
remote address, but Caddy leaves that address empty during early data. Connections finish the TLS
handshake before requests are forwarded; HTTP/3 and ordinary TLS session resumption remain enabled.

## 7. What is compiled, and what is still a setting

A projection earns its complexity only where it replaces a manual step.

| Surface | Compiled from the repository | Still configured in a UI |
|---|---|---|
| cluster dashboard, portal, Grafana, CrowdSec, ntfy | tiles, categories, URLs, dashboards, alerts, trusted subnets, accounts and tokens | nothing |
| Klipper | the machine definition and macros | calibration state |
| Home Assistant | integrations, MQTT | automations, the MCP server and Assist exposure; the reverse-proxy trust (`use_x_forwarded_for`, the ingress overlay address in `trusted_proxies`) - since 2026.8 the `http:` block migrates into the Home Assistant store once and is ignored afterwards |
| arr stack, Sabnzbd | quality profiles and custom formats (Recyclarr) | root folders, download clients, categories, paths |

The last rows are the difference between "the instance can be rebuilt" and "the instance behaves the
same afterwards". The reverse-proxy trust is the sharpest: without the ingress overlay address in
`trusted_proxies`, Home Assistant answers 400 to everything arriving through the ingress before it
handles anything. Re-enter it under *Settings - System - Network* after a lost store; the address is
the one the topology gives the ingress host (`10.10.100.1`), not a literal.

## 8. Observability

`cld-edge-01` runs the pipeline (Prometheus, Grafana, Loki, Alertmanager); `cld-ops-01` and
`hom-srv-01` run collectors (Alloy, node and blackbox exporters); the desktops run none - the ground
truth for fleet health is the server side. Alerting goes to the self-hosted ntfy instance, which also
carries Home Assistant, CrowdSec and arr-stack notifications. CrowdSec runs on both cloud hosts with
one bouncer per host and global decisions.

Three instruments state the promises and can disagree with the system:

- `checks.network-invariants` holds them against the evaluated fleet, and was verified by breaking it
  on purpose;
- `nix run .#network-audit` measures the running fleet and asks each host which path it uses;
- `nix run .#exposure-audit -- --strict` lists every listening socket outside loopback and says whether
  it is a decision or a question.

## 9. Data, backup, restore

| Copy | Where | How |
|---|---|---|
| working set | `hom-srv-01` | per-service state and data tiers |
| local snapshots | `hom-srv-01` | filesystem snapshots before a rebuild |
| offsite | Backblaze B2 | `restic`, nightly, encrypted client-side, object lock |

Restore is `restic restore` from the same repository; the passphrase lives in SOPS. A failed job is a
failed backup, so `systemctl --failed` is part of the health check.

## 10. Where things live

The repository layout is in [`../AGENTS.md`](../AGENTS.md); deploy, verify and recovery in
[operations.md](operations.md); users, access and the security model in [identity.md](identity.md); the
desktop hosts in [desktop.md](desktop.md); devices that cannot run NixOS in [embedded.md](embedded.md).
