# Architecture

> **Domain:** `vyrx.de` · **Overlay:** WireGuard `10.10.100.0/24` · **LAN supernet:** `10.10.0.0/16`
>
> This document defines the vocabulary the others use - host, zone, plane, contract, scope. It states
> how the system is, not how it was meant to be; where a statement is measured, the measurement is
> named, and where it is enforced, the invariant is named.

## 1. Principles

1. **Services, not machines.** A service owns a DNS name. Which host runs it is a deployment decision
   that may change without any consumer noticing - `jellyfin.vyrx.de` survived three host migrations.
   See §6 for the one rule that makes this work: names are derived from contracts, never written.
2. **Deterministic host names (RFC 1178).** `<location>-<role>-<index>`: `hom-srv-01`, `cld-edge-01`.
3. **One name, one answer per plane.** A public name resolves to the ingress from outside and to the
   LAN host from inside - split horizon, not two different names.
4. **Collision-free addressing.** `10.10.0.0/16` behind `10.10.100.0/24`, chosen so a roaming client
   can never collide with the network it happens to be attached to.
5. **The inventory decides.** Addresses, zones, names, firewall rules and DNS records are functions of
   `my.topology` and the contract projections. Writing an address twice means a derivation is missing.
6. **Self-hosted identity, no external control plane.** Authentik, ntfy and the WireGuard mesh replace
   SaaS identity, push and connectivity. There is no vendor in the data path.
7. **Evidence over intention.** Every claim in this documentation is either measured (the command is
   named) or asserted (the invariant is named). See [practices.md](practices.md).

## 2. Hosts

| Host | Role | Zone | Address | Mesh | Runs |
|---|---|---|---|---|---|
| `cld-edge-01` | server | `mesh` + public | `173.249.22.211` | `10.10.100.1` | Ingress (Caddy), Authentik core, CrowdSec master, observability stack, primary database, ntfy |
| `cld-ops-01` | server | `mesh` + public | `37.114.55.91` | `10.10.100.2` | Observability collector, Attic binary cache, OpenClaw gateways, CrowdSec agent |
| `hom-srv-01` | server | `infra` | `10.10.10.10` | `10.10.100.10` | LAN gateway (DHCP, DNS, NTP, NAT), media stack, Home Assistant, Klipper, local ingress, ESPHome flashing |
| `hom-wrk-01` | desktop | `corp` | `10.10.20.10` | `10.10.100.20` | Niri desktop, development environment |
| `mob-nb-01` | notebook | `corp` (roaming) | DHCP | `10.10.100.30` | Roaming client; reaches the LAN over the mesh |

Devices that cannot run NixOS but belong to the LAN (printers, relays, access points) are declared in
`my.topology.devices` and reconciled agentlessly; their own document is [embedded.md](embedded.md). A
device that cannot run NixOS but needs the **mesh** (a phone, a tablet) is not a LAN device: it has no
`ipv4`, only an overlay identity, and is declared in `my.topology.hosts` with `hostType = "client"`.
It is a node like the others; its WireGuard configuration is rendered as a wg-quick file
(`my.features.system.networking.wireguard.clientConfigs`) instead of a NixOS interface.

## 3. Network model

### 3.1 One Layer-2 segment, three zones

The house is **one flat Layer-2 segment**. Zones are *addressing and policy*, not separate broadcast
domains: a zone is a `/24` plus a trust level plus a set of firewall rules. There are no VLANs - the
hardware for a second segment does not exist yet, and the zone model is honest about that
([naming.md](naming.md) states this explicitly, because a naming document that implies isolation
nobody implemented is worse than no document).

| Zone | CIDR | Gateway | Trust | Contains |
|---|---|---|---|---|
| `infra` | `10.10.10.0/24` | `10.10.10.1` (uplink) | highest | `hom-srv-01`, the access point, the router |
| `corp` | `10.10.20.0/24` | `10.10.20.1` | trusted | workstations, phones, roaming clients |
| `iot` | `10.10.30.0/24` | `10.10.30.1` | isolated | printer, relays, 3D printer |
| `guest` | `10.10.99.0/24` | `10.10.99.1` | untrusted | guests, internet only |
| `mesh` | `10.10.100.0/24` | `10.10.100.1` | trusted transport | the overlay itself |

### 3.2 DHCP: the inventory decides the zone

`hom-srv-01` runs Kea. All served subnets live in **one shared network**, because Kea's default subnet
selection for a directly connected client uses the *receiving interface's address* and ignores client
classification entirely (ARM 8.6) - with an interface that carries an address in every zone, one zone
would win for everybody. Inside the shared network the class decides:

- one class per served zone, matched on the MAC addresses its inventory entries declare
  (`pkt4.mac == 0x…`);
- the default zone carries the **complement** class (`not member('infra') and not member('iot')`),
  because a subnet that names no class accepts every client and naming a class does not make a subnet
  preferred (ARM 8.4.2);
- `guest` is deliberately **not** served by this gateway: no host carries that zone.

Measured 2026-09-20: all seven inventarised devices hold the address their entry declares; a device
that is not in the inventory gets a default-zone lease - which is the rule, not a fallback.

### 3.3 The gateway

`hom-srv-01` is a single-NIC router-on-a-stick (RFC 1812): it is the default router for every zone, the
DHCP server, the resolver, the NTP server and the NAT for the trusted zones. The uplink is the router at
`10.10.10.1`, which is a transparent modem - no DHCP, no DNS handed to clients, no port forwardings.
Its DHCP toggle is off (verified over TR-064: `DHCP server current=False`), and the DNS it would
announce is not settable over TR-064 and reaches nobody while its DHCP is off.

IPv6 is deliberately absent from the LAN: this gateway is IPv4-only (Kea DHCPv4, no DHCPv6 and no
router advertisements) and the zones declare no IPv6 prefix, so the only IPv6 in the fleet is the
mesh's ULA (§4). Whatever the uplink announces over IPv6 reaches nothing and is not part of the model.

The zone gateways (`10.10.20.1`, `10.10.30.1`, …) are addresses *on that one interface*. Which zones a
host serves follows from its role, not from a list: a zone's gateway must live inside the zone, or it
cannot be installed as a default route at all.

### 3.4 Isolation

Isolation is enforced by the firewall and the trust model, not by segments:

- forwarding is enabled per zone and only for zones whose trust level permits it - `iot` and `guest`
  never transit;
- NAT for the uplink carries the trusted zones only;
- the IoT zone may answer requests from `hom-srv-01` (Home Assistant, Klipper) and reach the internet
  where it needs to, and nothing else.

## 4. The mesh

Kernel WireGuard, declaratively derived from `my.topology`. No control plane, no database, no vendor.

```
        cld-edge-01 10.10.100.1  ◄──────►  cld-ops-01 10.10.100.2      both public, both relays
              ▲                                    ▲
              │  dual-homed spokes, keepalive 25   │
      ┌───────┴────────┬───────────────┬───────────┘
  hom-srv-01      hom-wrk-01       mob-nb-01                     the LAN is behind hom-srv-01
  10.10.100.10    10.10.100.20     10.10.100.30
```

- **Dual hub.** Every host peers with both cloud hosts. The *primary* hub carries the overlay CIDR for
  transit; the secondary is reached by its own `/32`. A hub can be taken out without reconfiguring a
  spoke.
- **Longest-prefix cryptokey routing.** A peer's `allowedIPs` is its overlay address plus whatever it
  carries (§ below). Traffic to a host's own `/32` goes direct; traffic to a prefix goes to whoever
  carries it.
- **The mesh carries the zones that need it - and the inventory says which.** Not declared but
  derived: a zone is carried when it holds a device that has no overlay identity of its own. A
  printer, a relay or a microcontroller has one address and no second one, so a node outside the LAN
  reaches it only when its zone is routed. A host zone is never carried: its hosts answer at their
  overlay address, and carrying the zone would put every device behind them within reach of every
  mesh node. `my.topology.lanRouter` names the host that carries them, the way `ingressHost` names
  the ingress; `my.topology.announcedZones` is what it carries. Measured 2026-09-21: from a cloud
  node the printer resolves to its LAN address and `ping` and IPP reach it over `wg0`, while
  `hom-srv-01.node` answers its overlay address.
- **A host with its own address in a home zone installs no route for a carried zone**: its zone
  gateway reaches every other home zone directly, so a tunnel route would shadow that path.
- **A host that is at home uses the home LAN, even where the tunnel carries the same prefix.**
  Measured: systemd-resolved keeps answering through the door that answered last, and a carried `/24`
  beats a host's own default route by longest prefix - a route metric only orders equal prefixes. A
  roaming node therefore resolved LAN names to overlay addresses and reached the printer through the
  relays (65 ms). `features/system/networking/lan-preference` gives the link that holds an address in
  a home zone the home door as its own resolver with a default routing domain, and puts every carried
  zone the host is not itself inside on a route of the same prefix through that zone's gateway at
  metric 600. The link carries the *internal domain*, not everything: a second `~.` does not win
  against the global one (measured), while a more specific rule does. The dispatcher also resets
  systemd-resolved's server preference, because it otherwise keeps the door that answered last - which
  is what left the notebook attached to the home door while still receiving overlay addresses. Both are
  withdrawn when the address is gone. Measured 2026-09-21 after: printer 13 ms, `jellyfin.vyrx.de` ->
  `10.10.10.10`, `hom-wrk-01.node.vyrx.de` -> `10.10.20.10`, and `nix run .#network-audit` reports 20
  checks, 0 failed, with every host judged on the path it actually uses.
- **The mesh is the last resort.** The interface carries route metric 1000 against NetworkManager's
  600: a prefix the host can reach directly always wins, and the tunnel is used only when the LAN is
  elsewhere. Without it, a client at home would send LAN traffic out through the cloud and back.
- **IPv6 by design.** Alongside `10.10.100.0/24` the mesh spans `fd10:1000:100::/64` (RFC 4193 ULA).
- **MSS clamping** on both directions of the interface, so TCP handshakes survive mobile uplinks.

Two invariants hold the assumptions: at most one host may deliver a zone (cryptokey routing has exactly
one owner per prefix), and every delivered zone must be a `/24`, because membership is decided on the
network part.

## 5. DNS and certificates

### 5.1 Planes

| Plane | Names | Published where | Answers |
|---|---|---|---|
| public | `<service>.vyrx.de` | Cloudflare | the ingress |
| internal | `<service>.lan.vyrx.de`, `<service>.mesh.vyrx.de` | Blocky only, never Cloudflare | the LAN host, over the mesh for remote clients |
| node | `<host>.node.vyrx.de` | Cloudflare | the host's overlay address |
| user public | `*.pub.<user>.ai.vyrx.de`, `<user>.ai.vyrx.de` | Cloudflare | the user's OpenClaw gateway |

Public names are **flat at the apex**: the host that serves a name is never part of it. The normative,
machine-generated list is `my.contracts.projections.fqdns`; the derivation rules are
[naming.md](naming.md). Any enumeration in this document is illustrative.

### 5.2 Split horizon

The resolver on `hom-srv-01` (Knot Resolver 6, `features/services/dns`) answers **three planes** and
picks between them by the *source address* of the query, so one name has one address per plane:

| Plane | Source | What a name resolves to |
|---|---|---|
| `lan` | a home zone (`infra`, `corp`, `iot`) | the LAN address, so the packet stays local |
| `overlay` | the mesh (`10.10.100.0/24`, `fd10:1000:100::/64`) | the overlay address, reachable over `wg0` |
| `public` | anything else | the ingress for a `public` service, the overlay for a node |

A device has no overlay identity, so the `lan` plane answers its only address. A node outside the LAN
reaches it exactly when its zone is carried into the mesh (`announcedZones`), so the `overlay` plane
answers the same address then and stays silent otherwise: a name that resolves to an address nothing
routes would be worse than no answer. A cloud host's `ipv4` is its public
address and is never handed to a LAN client: the `lan` plane answers its overlay, which a home client
reaches through its LAN gateway. Blocklists are carried as an RPZ zone, converted from hosts format
and refreshed on a timer.

Cloudflare answers the public names with the ingress for everyone who does not ask us, so the family
path is unchanged.

The same name has two doors. A client at home reaches the resolver over the LAN - the `lan` plane,
so the answer is a LAN address and the packet stays local - and a client away from home reaches the
same resolver over DNS-over-TLS at the public door, where the ingress terminates the resolver's own
name and certificate (`features/services/dns`, the `dot` option). A client therefore configures one
name (a phone's private DNS setting is `dns.<domain>`) and is answered by the door its network can
reach. The views also carry `dst-subnet`, so the home plane is the door a query *arrived at*, not
merely where it came from: a foreign network that happens to use a home prefix is not treated as
being at home.

Measured 2026-09-21: `jellyfin.vyrx.de` -> `10.10.10.10` / `10.10.100.10` / `173.249.22.211`,
`hom-wrk-01.node.vyrx.de` -> `10.10.20.10` / `10.10.100.20`, and `hom-prn-01.node.vyrx.de` ->
`10.10.30.19` in the `lan` and the `overlay` plane alike, because that device's zone is carried into
the mesh - a device in a zone that is not carried is NXDOMAIN off the LAN rather than an address
nothing routes. Over DoT the public door answers the ingress for a service and NXDOMAIN
for a device, the home door the LAN addresses of both; both doors present a Let's Encrypt
certificate for the resolver's name.

Every host resolves through that resolver. The list is declared once in the inventory
(`my.topology.resolvers`) and `features/system/networking/static` hands it to **both** consumers:
`networking.nameservers` (which systemd-resolved and NetworkManager read) and
`networking.resolvconf.extraConfig` (openresolv, which is what actually owns `/etc/resolv.conf` on
NixOS and does **not** read the former). Declaring only the first left the file to whatever wrote it
last - a stale DHCP lease on `hom-srv-01` put the uplink's nameservers first and name resolution
timed out (measured 2026-09-21). A roaming host is not static, so it keeps the resolver of the
network it is on.

### 5.3 Certificates: one per name, issued where it terminates

There is no wildcard certificate here: Cloudflare's own Universal SSL owns the apex and the wildcard,
and DNS-01 for `_acme-challenge.vyrx.de` is therefore not ours to write (measured: the values are
published but absent from the zone API). The model is the per-consumer one, not a shared secret:

- each name's certificate is issued **on the host that terminates it**, so no key material is copied;
- the ingress validates with **HTTP-01** (the names resolve to it);
- hosts behind split horizon use **DNS-01** via the Cloudflare API, with the credential passed as a
  systemd credential, and the resolver pinned to `1.1.1.1:53` because lego determines the zone from the
  SOA and the system resolver would answer through the mesh;
- names outside the public zone fall back to `tls internal`;
- internal `.lan` names get public certificates too - they are subdomains of the public zone, and the
  trade-off (they appear in certificate transparency logs) is deliberate.

Measured 2026-09-20: `hom-srv-01` holds 14 certificates, `cld-ops-01` 12, and the ingress none of its
own beyond what Caddy obtains automatically.

## 6. Service contracts

A service declares what it offers and what it needs; the platform derives the rest. Nothing is written
twice, and no service module knows its host, its name or its neighbours.

| Declaration | Meaning | Projected to |
|---|---|---|
| `my.contracts.provides.<svc>.endpoints` | the interfaces a service exposes: port, protocol, scope (`public` / `internal` / `local`), authentication | DNS records, Caddy vHosts, firewall rules, health probes |
| `…storage` | persistence needs and their tier | storage contracts, backup sets |
| `…backup` | what must be restorable, with retention | restic jobs |
| `…telemetry` | what must be observable | Prometheus scrape targets, alerts |
| `my.contracts.consumes.<db>` | a database, a user, a bucket | provider resources, declared by the provider engine |

Consequences worth knowing:

- a service that declares `scope = "public"` gets a public name, a certificate and a proxy - it does
  not ask for them;
- services never reference a host, so moving one is a one-line change in `hosts/`;
- the FQDNs, the Caddy configuration, the Authentik blueprints and the backup jobs are all *functions*
  of these declarations, which is why a rename is a derivation change rather than a migration.

## 7. Configuration layout

```
flake.nix        inputs, overlays, one mkSystem call per host
hosts/<name>/    entry point: role + hardware + host-specific features
roles/           base → server | pc → desktop | notebook
features/        auto-discovered modules, each behind an `enable` option
contracts/       provides / consumes / naming / endpoints / storage / dependencies
lib/core/        mkSystem, recursive module discovery
user/<name>/     Home Manager: user packages, shell, editors
docs/            this specification
```

Every feature and contract is *loaded* on every host and *active* only where `enable` is set. That is
what makes `nix flake check` meaningful: a module that does not evaluate is caught for all five hosts at
once, whether or not any of them enables it.

The invariants (`contracts/*`) are evaluation-time assertions, not conventions: a service from the
public plane without authentication, a name that cannot be derived, an endpoint on a host that does not
serve it, or a subnet a reservation falls outside - each fails the build rather than the deployment.

### 6.1 What is compiled, and what is still a setting

A projection earns its complexity only where it replaces a manual step. Measured 2026-09-20, service by
service:

| Surface | Compiled from the repository | Still configured in a UI |
|---|---|---|
| cluster dashboard (Homarr) | tiles, categories, icons and URLs from `endpoints.dashboard` | nothing |
| Grafana | three dashboards as files, plus datasources and alerts from the module | nothing |
| CrowdSec | the trusted-subnet whitelist, from `my.topology.trustedSubnets` | nothing |
| ntfy | accounts and tokens from SOPS, `deny-all` by default | nothing |
| Klipper | the machine definition and macros from the store | calibration state - the `runtime_variables.cfg` include is prepared but commented out |
| Home Assistant | integrations, MQTT, the reverse-proxy configuration | **automations**: the module includes them in UI mode, so they are not in Git, not reviewed, and do not survive a reinstall |
| arr stack, Sabnzbd | quality profiles and custom formats (Recyclarr) | root folders, download clients, categories, paths - only the secrets are templated |

The two gaps in the last rows are real and worth being explicit about: they are the difference between
"the instance can be rebuilt" and "the instance behaves the same afterwards". Neither is blocked by
anything except the work.

## 8. Observability

`cld-edge-01` runs the full pipeline (Prometheus, Grafana, Loki, Alertmanager); `cld-ops-01` and
`hom-srv-01` run collectors (Alloy, node and blackbox exporters). The desktops run none - the ground
truth for "is the fleet healthy" is the server side, and a laptop that is switched off is not an
incident.

Alerting goes to the self-hosted ntfy instance (`push.vyrx.de`), which also carries Home Assistant,
CrowdSec and arr-stack notifications. CrowdSec runs on both cloud hosts and shares a bouncer per host;
its decisions are global.

## 9. Data, backup, restore

Three copies, and the tiers are storage contracts rather than directory conventions:

| Copy | Where | How |
|---|---|---|
| working set | `hom-srv-01` | per-service state and data tiers |
| local snapshots | `hom-srv-01` | filesystem snapshots before a rebuild |
| offsite | Backblaze B2 | `restic`, nightly, encrypted client-side, object lock |

Restore is `restic restore` from the same repository; the passphrase lives in SOPS. A failed job is a
failed backup - `systemctl --failed` is part of the health check, not an optional extra (one run was
silently lost to a DNS outage and only showed up in that list).

## 10. Where the other documents take over

| Topic | Document |
|---|---|
| What a name may look like and who owns it | [naming.md](naming.md) |
| Users, service accounts, authentication flows | [identity.md](identity.md) |
| The security model, layer by layer | [security.md](security.md) |
| Microcontrollers, access point, router | [embedded.md](embedded.md) |
| Interfaces, tokens, typography | [design.md](design.md) |
| Deploy, verify, recover | [operations.md](operations.md) |
| The engineering bar and the known failure patterns | [practices.md](practices.md) |
