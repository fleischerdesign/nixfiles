# VYRX — DNS, Host & Service Naming Specification

> **Status:** Normative derivation rules and enforcement for the naming intent declared in
> `architecture.md`. The parent specification defines **what names must express**; this
> document defines **how they are derived** and **how conformance is enforced**.
>
> **Authority split (three distinct questions):**
> * *What should a name express?* → `architecture.md` is authoritative (planes,
>   service-first principle, split horizon, projection engines).
> * *How is it derived and how is it checked?* → this document is authoritative; the parent
>   specifies intent but neither a derivation function nor any verification.
> * *What does the code actually do?* → neither: where the implementation contradicts
>   `architecture.md`, **the implementation is the defect**, not the specification (§0.2).
>   A documented decision is evidence of intent, not proof of correctness.
>
> **Companion documents:** `architecture.md` §1 (principles), §3 (edge diagram),
> §5 (split horizon), §8.1 (projection engines), `identity.md`, `operations.md`.

---

## 0. What this document is

Names here are **derived, not maintained**. An FQDN is a function of the topology and the contract
projections, which is what makes a host rename a derivation change rather than a migration with a
checklist. Where the code and this document disagree, the code is right and this is a bug.

The rules are enforced at evaluation time (`contracts/naming/*`), not left as conventions:

| Invariant | What it prevents |
|---|---|
| a public endpoint without authentication must declare why | an accidentally open service |
| every endpoint name is derivable from its contract | hand-written names that drift from the service |
| no name carries a host label | coupling a service to the machine that happens to serve it |
| internal planes are never projected into the public zone | leaking an internal name into Cloudflare |

This section used to quote the architecture document and list where the implementation contradicted
it. That drift has been fixed, so the quotes and the list are gone with it: the only thing worse than
an undocumented rule is a document describing a violation that no longer exists.

## 1. Planes (visibility boundaries)

| Plane | `scope` value | Suffix | Authoritative | Published in Cloudflare | Reached via |
|---|---|---|---|---|---|
| public | `"public"` | `vyrx.de` (apex) | Cloudflare | **yes** | ingress host (reverse proxy) |
| lan | `"internal"` | `lan.vyrx.de` | Blocky (split DNS) | **no** | home LAN |
| mesh | `"mesh"` | `mesh.vyrx.de` | Blocky + our overlay DNS | **no** | WireGuard mesh |
| iot | — *(device inventory, not an endpoint scope)* | `iot.vyrx.de` | Blocky | **no** | IoT segment |
| node | — *(host plane from `my.topology.hosts`, device plane from `my.topology.devices`)* | `node.vyrx.de` | Cloudflare | **yes** | CNAME → overlay (VPN) address; SSH/admin only (§2) |
| isolated | `"isolated"` | — | — | no | direct address/port only |

The `scope` enum is the **existing** contract enum (`contracts/endpoints/default.nix`):
`public | internal | mesh | isolated` (default `internal`). This specification does **not**
change it — it only maps it to suffixes (§3). `iot` is deliberately *not* an endpoint scope:
IoT names come from the device inventory and use the same `node` plane the hosts use
(`deviceFqdn(device) = "${name}.node.${domain}"`, e.g. `hom-prn-01.node.vyrx.de`).

A device in a zone the mesh **carries** (`my.topology.announcedZones`) is a different case from a
host: it has one address and no overlay identity, and a member that is not in the LAN reaches it
through the mesh. Its name is therefore published and answered like a host's - on the `node` plane,
with that one address - and it is answered in the `public` plane as well, because a roaming client's
resolver *is* the public door (its private-DNS name resolves to the public address and its queries
arrive there). The address stays unrouted outside the overlay, so the record is a location for
members, not an offer. A device whose zone is not carried is published nowhere but the LAN.

Rules:

* The suffix is the **only** thing that encodes visibility. It never encodes a host.
* `lan`/`mesh` exist **only** on our own resolvers and must never be published (§5.1); a `node` name is
  published, and for a carried device it names the LAN address a member reaches through the mesh.
* `mesh` is **our** overlay namespace, carried by WireGuard. Tailscale was retired on 2026-09-20; the
  `mesh` plane is authoritative in our own DNS — **no MagicDNS dependency**.

---

## 2. Host names

The host plane is `<host>.node.vyrx.de`: one record per host, pointing at that host's overlay
address ([architecture.md](architecture.md) §5.1). Therefore:

```
hostFqdn(host) = "${hostname}.node.${domain}"      # cld-edge-01.node.vyrx.de
                                                   # hom-srv-01.node.vyrx.de
record         = CNAME -> host's overlay (VPN) address
```

Consequences:

* Host FQDNs are **derived from the RFC 1178 hostname** (`architecture.md` §2) and live in a
  dedicated plane: a new host needs one inventory entry and collisions are structurally
  impossible.
* `node` names target the **overlay address** on purpose (admin access from anywhere over the
  mesh). They are published but unreachable without a mesh route — which is why they are
  exempt from I4.
* The hand-written, host-encoded `domain` values (`srv`, `wrk`, `nb`, `rt`, `ap`) and the
  labels `edge` / `ops` are **not part of §3**. `edge` / `ops` are load-bearing today (they
  are the `caddy.baseDomain` of the ingress hosts and appear throughout the docs) but are
  undeclared drift: they should either become aliases of the node name or be dropped once
  service names are flat (§3).

---

## 3. Service names

An endpoint's name is derived from `scope` (the plane) and `subdomain`:

```
fqdn(endpoint) =
  if endpoint.subdomain == null           then null    # scrape/direct-only, no name
  else if endpoint.scope == "isolated"    then null
  else "${endpoint.subdomain}.${planeSuffix(endpoint.scope)}"
```

`planeSuffix` is a pure mapping of the **unchanged** contract enum:

| `scope` | suffix |
|---|---|
| `"public"` | *(none — apex)* |
| `"internal"` | `lan.` |
| `"mesh"` | `mesh.` |
| `"isolated"` | — (no name) |

`endpoint.domain` and `my.features.services.caddy.baseDomain` are **removed from the naming
path**: `scope` *is* the plane, so the name never depends on placement.

| Service | Contract | Derived FQDN |
|---|---|---|
| Authentik | `scope = "public"; subdomain = "auth"` | `auth.vyrx.de` |
| ntfy | `scope = "public"; subdomain = "push"` | `push.vyrx.de` |
| Attic | `scope = "public"; subdomain = "cache"` | `cache.vyrx.de` |
| SearXNG | `scope = "public"; subdomain = "search"` | `search.vyrx.de` |
| **Jellyfin** | `scope = "public"; subdomain = "jellyfin"` | **`jellyfin.vyrx.de`** (public, as specified in §1.1/§3) |
| Home Assistant | `scope = "public"; subdomain = "hass"` | `hass.vyrx.de` (split horizon, §5) |
| Mealie | `scope = "internal"; subdomain = "mealie"` | `mealie.lan.vyrx.de` (as specified in §3 l. 89) |
| Sonarr | `scope = "internal"; subdomain = "sonarr"` | `sonarr.lan.vyrx.de` (as specified in §1.1) |
| OpenClaw (philipp) | `scope = "public"; subdomain = "philipp.ai"` | `philipp.ai.vyrx.de` |
| Prometheus scrape target | `subdomain = null` | — (direct overlay address) |

### 3.1 `scope = "public"` does **not** mean "host has a public address"

It means **terminated by the ingress host**. This is the documented Ingress Engine:
the ingress publishes the vhost and proxies to the provider over the WireGuard mesh
("geroutet via VPN zu `hom-srv-01`"). A `public` endpoint on a LAN host is therefore
correct — provided the ingress has a mesh route to that host.

The consequence for projection: **public records always point at the ingress**, and the
ingress backend address is derived from the provider's reachability (LAN address if the
ingress shares the L2 segment, otherwise the mesh address).

---

## 4. Split horizon (one name, two answers)

| Resolver | `public` name | `lan` / `mesh` / `iot` name |
|---|---|---|
| Cloudflare | ingress public IPv4 | *(NXDOMAIN — not published)* |
| Blocky (local) | provider LAN/overlay IPv4 (split-horizon rewrite) | provider address in that plane |

This is what makes `jellyfin.vyrx.de` resolve to `10.10.10.10` at home and to the ingress
abroad (documented in §5), and it removes the entire `.lan`-duplicate class of aliases such
as `mon.lan.vyrx.de` / `grafana.ops.vyrx.de`.

---

## 5. Wildcards

Wildcards are **part of the design** (see the documented `*.mesh.vyrx.de`). What is *not*
part of the design is a wildcard that encodes a **host** into a **service** namespace.

| Wildcard | Status | Purpose |
|---|---|---|
| `*.${domain}` → ingress | **kept** (exactly one) | catch-all for the public plane; never shadows a projected name |
| `*.mesh.${domain}` | **kept** (documented) | overlay namespace |
| `*.${service}.${domain}` | **kept**, service-declared via `extraDomains` | runtime-minted names (OpenClaw self-publishing `<app>.pub.<inst>.ai.vyrx.de`) |
| `*.edge.${domain}`, `*.ops.${domain}` | **abolished** | these only existed because service names encoded hosts |

A wildcard **certificate** for the public plane is **not obtainable here**, and that is a
measurement, not an assumption: Cloudflare's own Universal SSL certificate for this zone is
validated by TXT records at `_acme-challenge.${domain}`, which Cloudflare manages internally and
which do not appear in the zone's API record list (verified: DNS serves them, the API does not know
them). No third party can prove control of that name, so neither `*.${domain}` nor the apex can be
issued to us. Per-name challenges are free and publish within seconds
(`_acme-challenge.<name>.${domain}`, verified), so **every public name gets its own certificate,
issued on the host that terminates it** — which is also how the rest of the industry avoids
copying private keys between hosts (one policy, per-consumer credentials: SPIRE, Vault PKI,
cert-manager).

The criterion is **not** the scope but whether the name lies inside the zone this API manages: only
then can `_acme-challenge.<name>` be published, and DNS-01 does not care where the name itself
resolves. Internal-plane names are subdomains of the public zone, so they qualify like any other -
which is why no vhost needs Caddy's own CA.

| Plane | Certificate |
|---|---|
| public | one per name, issued on the terminating host via DNS-01 (never a wildcard) |
| internal (`.lan`, `.mesh`) | one per name as well, from a public CA. Not reachable from outside — measured: every `.lan` name is NXDOMAIN publicly while the internal resolver answers it — but a **publicly trusted** certificate, so no client has to trust a private CA |
| outside the managed zone | Caddy's own CA; no credential here can publish a challenge in a zone we do not manage |
| multi-label public (`<app>.pub.<inst>.ai.${domain}`) | one per name as well; OpenClaw's dynamically minted hosts keep Caddy `on_demand_tls` (code §8.1) |

**The deliberate trade-off:** a certificate says nothing about reachability, but Certificate
Transparency logs publish every name a public CA issues for. Internal names therefore become
*enumerable* (not reachable) once they hold public certificates. That is accepted here because these
names are not secret - `sonarr`, `mainsail`, `moonraker` are guessable by design - and because the
alternative, a private CA, would require trusting that CA on every client device, which is the
friction this design exists to avoid. Where an internal name was only a convenience, the public name
plus split horizon serves the same purpose without a second name at all.

### 5.1 The public catch-all conflicts with the internal planes (verified defect)

**What the internal resolver does with undeclared names (measured 2026-09-20).** Blocky's `customDNS`
resolves subdomains of a mapped name automatically, and the apex `${domain}` is itself mapped (the
landing endpoint terminates on the ingress). Every `*.${domain}` therefore resolves to the ingress
internally, declared or not: `zzz-nonsense-4711.${domain}` answers `10.10.100.1` inside the LAN while
publicly returning NXDOMAIN. This is deliberate — a single refusal point instead of a DNS failure —
and it discloses nothing beyond the existence of the zone. The ingress refuses a name it does not
serve (TLS alert `internal error`, no certificate), which is why a mistyped public name shows as
`ERR_SSL_PROTOCOL_ERROR` in a browser rather than as a certificate for a name we do not own. Removing
this would mean un-mapping the apex and losing internal resolution for `${domain}` itself, so it
stays - and is recorded here so the spec and the behaviour agree.

**Zones are addressing and policy, not a boundary (measured).** On one flat L2 every zone's subnet
shares the broadcast domain, so devices in different zones reach each other directly and never pass
the gateway - the firewall governs what is *routed*, not what is adjacent. A zone therefore decides:
which DHCP options a device receives (router, DNS, NTP), which names resolve for it, and which
firewall rules apply to its traffic that leaves the segment. It does not isolate. Real isolation for
the untrusted plane needs its own L2 - VLANs or a second segment - and the cutover documents that
as the open decision rather than implying a boundary that does not exist.

**Which zone a device lands in is declared, not incidental (implemented 2026-09-20).** Kea
receives several subnets on one interface and picks by criterion: before this change it simply took
the first matching subnet in configuration order, so devices declared `infra` or `iot` were handed
corp addresses and their own reservations were never reached - a silent mismatch between inventory
and wire. Each
served zone is now a Kea client class matched on the MAC addresses its inventory entries declare,
its subnet accepts only that class, and exactly one subnet - `defaultZone`, default `corp` - stays
unrestricted for clients the inventory does not name. The order of the subnet list no longer has any
effect; adding a device is one inventory line (`zone`, `mac`, `ipv4`), which simultaneously feeds its
DHCP class, its reservation, its DNS name and its firewall treatment.

RFC 4592 resolves wildcards by *closest encloser*, so an apex wildcard `*.${domain}` absorbs
names that merely look like they belong to an internal plane. **Verified live** (Cloudflare
DoH): `foo.lan.vyrx.de`, `bar.mesh.vyrx.de` and `x.iot.vyrx.de` **all resolve to the ingress**.
The internal planes are therefore *not* isolated today, and the obvious-looking claim
"internal planes return NXDOMAIN publicly" is empirically false.

Exactly one of these must be chosen before I4/I5 can be enforced:

* **A — explicit public names, no catch-all.** Publish only intended public names;
everything else is NXDOMAIN. Maximum isolation, at the cost of a new service needing a
record before it is reachable.
* **B — keep the catch-all, delegate the internal planes.** Create `lan`/`mesh`/`iot` NS
records pointing at the internal resolver so the planes *fail closed* (SERVFAIL) instead of
leaking to the ingress.

Until this decision is recorded, the internal planes are aspirational.

---

## 6. Aliases & renames

```nix
my.contracts.provides.<service>.endpoints.<name>.aliases = [ "push.edge" ];
```

An alias is a CNAME to the endpoint's derived FQDN in the same plane, and is projected
identically by every engine (Caddy, DNS, Authentik redirect URIs). Renames are therefore
additive and reversible: publish new + old → migrate consumers → verify → drop the alias.
Aliases are tracked as deprecation debt and reported by §7 I8.

---

## 7. Invariants (evaluation-time, hard failures)

| # | Invariant |
|---|---|
| I1 | Host FQDNs are unique and derived from unique RFC 1178 hostnames. |
| I2 | No two endpoints derive the same FQDN; no alias collides with a canonical name. |
| I3 | A `public` endpoint's provider is reachable from the ingress (LAN or mesh address present). **Not** "provider has a public address" — see §3.1. |
| I4 | The Cloudflare record set contains only `public`-plane names (no `lan.`/`mesh.`/`iot.` suffix). |
| I5 | The Cloudflare record set contains at most one `*` catch-all, pointing at the ingress, and it must not absorb the internal planes (§5.1). |
| I6 | Every projected record's FQDN lies inside a declared plane suffix. |
| I7 | `scope ∈ { public, internal, mesh, isolated }` — the **existing** contract enum, unmapped (`iot` is not an endpoint scope). |
| I8 | Aliases are enumerated in a deprecation report. The subnet-migration debt report (I11) that used the same mechanism retired with its subject on 2026-09-20: there is no migration scaffolding left to report. |
| I9 | A `public` endpoint with `auth = "none"` must carry an explicit `publicExempt = "<reason>"`. Publishing an unauthenticated service to the internet is a **decision**, never a default. |

Read-only projections for inspection and tests: `my.contracts.projections.fqdns`,
`…hostFqdns`, `…dnsRecords.{public,lan,mesh,iot}`, `…ingressVhosts`.

---

## 8. API delta

| Today | Target |
|---|---|
| `endpoints.<n>.domain` (defaults to `caddy.baseDomain`) | removed |
| `my.features.services.caddy.baseDomain` | removed |
| `my.topology.hosts.<h>.domain` (hand-written abbreviation) | derived from hostname; `aliases` instead |
| `scope` enum (`public\|internal\|mesh\|isolated`) | **unchanged** — suffixes are derived by mapping (§3); no contract churn |
| hardcoded `"<svc>.edge.${domain}"` fallbacks in features | removed |
| host-encoded service wildcards | removed (§5) |
| `my.topology.hosts.<h>.zone` (VLAN/trust) | unchanged — orthogonal to DNS planes |

---

## 9. Decisions

1. **Overlay naming:** `mesh.vyrx.de` is authoritative in our own DNS. **The overlay is WireGuard
   only** — Tailscale was retired on 2026-09-20 and its ULA prefix
   transitional and will be removed** — no MagicDNS dependency. *(resolved)*
2. **Public IPv6:** resolved factually — neither `cld-edge-01` nor `cld-ops-01` announces a
   global unicast IPv6 prefix (verified: only `tailscale0` ULA `fd7a::/…` and `wg0` ULA
   `fd10:1000:100::/64`). **No `AAAA` records in the public plane** until a provider prefix
   exists; the `mesh` plane keeps its `fd10::/64` ULA records.
3. **Mail zone** (`MX`, `SPF`, `DKIM`, `DMARC`, `PTR`): still needs an explicit, documented
   place in the apex before mail features grow. *(open)*

---

