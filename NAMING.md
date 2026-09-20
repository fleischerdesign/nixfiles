# VYRX — DNS, Host & Service Naming Specification

> **Status:** Normative derivation rules and enforcement for the naming intent declared in
> `ARCHITECTURE.md`. The parent specification defines **what names must express**; this
> document defines **how they are derived** and **how conformance is enforced**.
>
> **Authority split (three distinct questions):**
> * *What should a name express?* → `ARCHITECTURE.md` is authoritative (planes,
>   service-first principle, split horizon, projection engines).
> * *How is it derived and how is it checked?* → this document is authoritative; the parent
>   specifies intent but neither a derivation function nor any verification.
> * *What does the code actually do?* → neither: where the implementation contradicts
>   `ARCHITECTURE.md`, **the implementation is the defect**, not the specification (§0.2).
>   A documented decision is evidence of intent, not proof of correctness.
>
> **Companion documents:** `ARCHITECTURE.md` §1 (principles), §3 (edge diagram),
> §5 (split horizon), §8.1 (projection engines), `IDENTITY.md`, `DEPLOYMENT.md`.

---

## 0. Intent, implementation, and gaps

### 0.1 Specified intent (quoted from `ARCHITECTURE.md`)

* **§1.1 (l. 14) — Service-First statt Host-First:**
  "Dienste besitzen feste DNS-Endpunkte (`jellyfin.vyrx.de`, `sonarr.lan.vyrx.de`).
  Sie sind **niemals an physische Rechnernamen gekoppelt**."
* **§3 (l. 69) — zone diagram:** public names (`jellyfin.vyrx.de`) and a mesh namespace
  `*.mesh.vyrx.de (Mesh VPN)`.
* **§3 (l. 79):** "`jellyfin.vyrx.de` ➔ Jellyfin Media Streaming (**gesichert, geroutet via
  VPN zu `hom-srv-01`**)."
* **§3 (l. 89):** "`paperless.lan.vyrx.de` / `mealie.lan.vyrx.de`" — internal services live
  under `.lan`.
* **§5 (l. 154) — split horizon:** "Zuhause (VLAN 10/20): `jellyfin.vyrx.de` oder
  `hass.vyrx.de` **löst direkt lokal auf `10.10.10.10` auf** (volle LAN-Performance, keine
  Latenz, kein Hairpin-NAT)."
* **§8.1 — projection engines:**
  * *Ingress Engine (`cld-edge-01`)*: "projiziert clusterweit alle `scope = "public"` Endpoints
    in Caddy-VHosts **und WireGuard-Upstreams**" — `VHosts = Π_public(ClusterContracts)`.
  * *DNS Engine (`hom-srv-01`)*: "projiziert alle internen Endpoints und
    **Split-Horizon-Rewrites** in Blocky-Hosts" — `DNSRecords = Π_dns(ClusterContracts)`.
  * *Module neutrality:* "Feature-Module sind strikt **agnostisch** und passiv. Ein Modul
    kennt weder seinen Zielhost, noch Routing-Details, noch die Caddy-Konfiguration."

### 0.2 The implementation contradicts the specified intent (verified)

| Specified intent | Actual implementation | Consequence |
|---|---|---|
| §1.1: services are never coupled to machine names | `caddy.baseDomain` (`edge.` / `ops.`) → `push.edge.vyrx.de`, `grafana.edge.vyrx.de`, `cache.ops.vyrx.de` | every host migration becomes a rename (DNS + vHost + OIDC redirect URI + bookmarks); observed: stale `grafana.ops.…`, orphan `mon.lan.…`, `push.edge…` vs documented `push.vyrx.de` |
| §1.1 example `sonarr.lan.vyrx.de` | `sonarr.srv.lan.vyrx.de` | host label injected into the service name |
| §3 example `hass.vyrx.de` | `hass.srv.lan.vyrx.de` | same |
| §8.1: modules know neither their host nor routing | `plausible`, `linkwarden`, `vaultwarden`, `couchdb`, `obsidian-livesync` hardcode `"<svc>.edge.${domain}"` | placement knowledge leaked into service modules |
| §8.1: Ingress Engine projects **all** `public` endpoints cluster-wide into vHosts **and WireGuard upstreams** | the DNS/Caddy projection is host-local; no ingress upstreams exist | `public` endpoints on LAN hosts produce **no** record — `jellyfin.vyrx.de` does not exist although §3 requires it |
| §5: `jellyfin.vyrx.de` resolves locally to `10.10.10.10` | Blocky maps `host.domain` only, not service names | the specified split horizon for service names is not implemented |
| §2: deterministic host naming | host FQDNs hand-written (`edge`, `ops`, `srv`, `wrk`, `nb`, `rt`, `ap`) | the documented node plane `*.node.vyrx.de` (§3.3) is not implemented at all |
| §3.1 marks `seerr`, `hass` public; §3.2 marks `mealie`, `mon` internal | contracts evaluate to `jellyseerr=internal`, `home-assistant=internal`, `mealie=public`, `grafana=public` (+ orphan `mon.lan` extraDomain) | **4 of the 11 documented zone members are classified the other way round** — zone membership is not actually driven by §3 |

### 0.3 Where the parent specification is **under**-specified

These are the additions this document contributes. They are not restatements of
`ARCHITECTURE.md` — the parent is silent on them, and that silence is why the drift in §0.2
could go unnoticed:

1. **Derivation functions.** The parent fixes hostnames (§2) and gives naming *examples*,
   but defines neither a host-FQDN rule nor a service-FQDN rule. §2/§3 below are those rules.
2. **Zone authority and publishing.** The parent names the planes and locates the DNS engine
   on `hom-srv-01`, but never states who is authoritative for `lan`/`mesh`/`iot` or whether
   they may be published. §1 fixes that (Blocky-only, never published).
3. **A plane for cloud-internal services.** The parent's model has no plane for services that
   are reachable only over the overlay and are not internet-facing (Prometheus, PostgreSQL,
   Redis on the cloud hosts). §3 resolves them (`subdomain = null` → no name).
4. **Enforcement.** The parent states principles but no invariants, and nothing failed when the
   implementation violated them. §7 makes conformance a hard evaluation failure.
5. **Bindings to the engines.** §8.1 declares the Ingress/DNS engines as intent; §5/§6 here
   turn them into concrete record/vhost/upstream projections, including the missing
   ingress → mesh upstream path.

---

## 1. Planes (visibility boundaries)

| Plane | `scope` value | Suffix | Authoritative | Published in Cloudflare | Reached via |
|---|---|---|---|---|---|
| public | `"public"` | `vyrx.de` (apex) | Cloudflare | **yes** | ingress host (reverse proxy) |
| lan | `"internal"` | `lan.vyrx.de` | Blocky (split DNS) | **no** | home LAN |
| mesh | `"mesh"` | `mesh.vyrx.de` | Blocky + our overlay DNS | **no** | WireGuard mesh |
| iot | — *(device inventory, not an endpoint scope)* | `iot.vyrx.de` | Blocky | **no** | IoT segment |
| node | — *(host plane, from `my.topology.hosts`)* | `node.vyrx.de` | Cloudflare | **yes** | CNAME → overlay (VPN) address; SSH/admin only (§2) |
| isolated | `"isolated"` | — | — | no | direct address/port only |

The `scope` enum is the **existing** contract enum (`contracts/endpoints/default.nix`):
`public | internal | mesh | isolated` (default `internal`). This specification does **not**
change it — it only maps it to suffixes (§3). `iot` is deliberately *not* an endpoint scope:
IoT names come from the device inventory (`my.topology.devices[].domain`, e.g.
`rly-01.iot.vyrx.de`).

Rules:

* The suffix is the **only** thing that encodes visibility. It never encodes a host.
* `lan`/`mesh`/`iot` exist **only** in Blocky and must never be published (§5.1).
* `mesh` is **our** overlay namespace, carried by WireGuard. Tailscale was retired on 2026-09-20; the
  `mesh` plane is authoritative in our own DNS — **no MagicDNS dependency**.

---

## 2. Host names

`ARCHITECTURE.md` §3.3 specifies the host plane:

> **§3.3 Node Management: `*.node.vyrx.de`** — "Feste CNAMEs auf die jeweiligen VPN-IPs für
> SSH- und Administrationszugriffe: `cld-edge-01.node.vyrx.de`, `cld-ops-01.node.vyrx.de`,
> `hom-srv-01.node.vyrx.de`, etc."

Therefore:

```
hostFqdn(host) = "${hostname}.node.${domain}"      # cld-edge-01.node.vyrx.de
                                                   # hom-srv-01.node.vyrx.de
record         = CNAME -> host's overlay (VPN) address
```

Consequences:

* Host FQDNs are **derived from the RFC 1178 hostname** (`ARCHITECTURE.md` §2) and live in a
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

## 9. Migration (staged, reversible)

| Stage | Change |
|---|---|
| 0 | This document, the read-only projections and invariants I1–I8 in **report-only** mode. No behaviour change. |
| 1 | Publish the derived names **in addition** to the current ones (via `aliases`). Everything keeps working. |
| 2 | Migrate consumers to the documented names (`jellyfin.vyrx.de`, `push.vyrx.de`, `hass.vyrx.de`, `sonarr.lan.vyrx.de`, …): Caddy vhosts from the projection, OIDC redirect URIs, Blocky mappings, `home.nix` shortcuts, client defaults. |
| 3 | Enable I3/I4/I5 as hard failures; reclassify endpoints (`internal`→`lan`, wrong planes). |
| 4 | Remove legacy names, `baseDomain`, `endpoints.<n>.domain`, `*.edge`/`*.ops`, then run the Cloudflare projection with `--prune` after verification. |

Ingress host (Cloudflare + Caddy) deploys last, so DNS/TLS never point at an unserved name.

---

## 10. Decisions

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

## 12. Implementation status

Verified against the running evaluation (`nix flake check`, fleet-wide):

| Rule | Implementation |
|---|---|
| §2 host plane | `nodeRecords` in the Cloudflare feature project `<hostname>.node.<domain>` → overlay address. |
| §3 service plane | `contracts/endpoints` derives `canonicalDomain` from `scope` + `subdomain` (`public`→apex, `internal`→`.lan`, `mesh`→`.mesh`, no subdomain/`isolated`→no name). `endpoint.domain` and `caddy.baseDomain` are removed from the naming path; the latter no longer exists. |
| §4 split horizon | Blocky projects every named endpoint fleet-wide to the address a LAN client should use; `.lan`/`.mesh`/`.iot` exist only there. |
| §5 wildcards | One opt-in apex catch-all (`catchAll`, default **off**), plus service-declared dynamic wildcards. Host-encoded service wildcards are gone. |
| §5.1 catch-all conflict | Resolved as option **A**: the catch-all is disabled, so internal planes return NXDOMAIN instead of being absorbed. |
| §6/§8.1 ingress engine | The ingress host publishes every fleet-wide `public` endpoint and proxies to the provider over the LAN/overlay (verified: `jellyfin.vyrx.de → 10.10.10.10:8096`, `cache.vyrx.de → 10.10.100.2:8080` with `flush_interval -1`, `hass.vyrx.de` with forward-auth). `my.topology.ingressHost` is the single SSOT. |
| §7 invariants | I1–I4, I9 enforced as assertions; I8 exposed as `my.contracts.projections.aliases`. |
| §8 API delta | Done, except that the `scope` enum is unchanged (mapped, not renamed — the overlay plane is spelled `mesh`, see §1). |
| §10.4 decisions | `hass`, `seerr`, `mealie`, `grafana` are public; `hass`/`seerr` moved behind Authentik forward-auth in the same change. |

Not yet deployed: all of the above is repository state and evaluation-verified only.
4. **Zone membership — resolved.** `hass`, `seerr`, `mealie` and `mon` (Grafana) are **public**.
   `ARCHITECTURE.md` §3.2 is therefore stale for `mealie`/`mon` (they belong in §3.1). Contract
   deltas:

   | Service | Current | Required | Resulting FQDN |
   |---|---|---|---|
   | `home-assistant` | `scope = "internal"; auth = "none"` | `scope = "public"; auth = "authentik"` (+ `unauthenticatedPaths` for the companion-app/token APIs) | `hass.vyrx.de` |
   | `jellyseerr` | `scope = "internal"; auth = "none"` | `scope = "public"; auth = "authentik"` | `seerr.vyrx.de` |
   | `mealie` | `scope = "public"; auth = "oidc"` | unchanged | `mealie.vyrx.de` |
   | `grafana` | `scope = "public"; auth = "oidc"` (+ `mon.lan` alias) | unchanged; drop the `mon.lan` alias (§4) | `grafana.vyrx.de` |

   **Critical:** `home-assistant` and `jellyseerr` currently pair `scope = "public"`-intent with
   `auth = "none"`. Changing only the scope would publish both **unauthenticated** on the
   internet. The scope and the auth must change together — this is exactly the class of mistake
   I9 exists to prevent.

   Operational caveat for `home-assistant`: the companion app and integrations authenticate with
   long-lived tokens, not a browser SSO redirect. Authentik forward-auth must therefore be
   combined with `unauthenticatedPaths` (and the already-configured `trusted_proxies`), or the
   mobile app breaks. The exact path list must be taken from Home Assistant's documented
   trusted-proxy setup, not guessed.

5. **Auth exemption mechanism (new, required by I9):** `public` + `auth = "none"` stays legal
   for self-authenticating or intentionally public endpoints (Attic's own token auth, `search`,
   the static `portfolio` / `vyrx-landing` sites). Those must declare `publicExempt = "<reason>"`
   so the exemption is visible in review rather than assumed.

---

## 11. Known gaps (this document is not yet "done")

Honest status. These are the open items that keep this specification short of the standard it
claims:

| # | Gap | Needed to close it |
|---|---|---|
| G1 | ~~Unenforced~~ **closed.** I1–I4 and I9 are hard assertions in `contracts/naming/default.nix`, evaluated fleet-wide on every host: `nix flake check` now fails cluster-wide on any violation. I9 immediately surfaced 14 pre-existing unauthenticated public endpoints, which are now declared with a reason. | I5–I8 remain reports (I8 is `my.contracts.projections.aliases`). |
| G2 | **Partially closed.** `NAMING.md` is the normative derivation, `ARCHITECTURE.md` §3.1 defers to `my.contracts.projections.fqdns`, and `caddy.baseDomain` / `endpoints.<n>.domain` are gone from the naming path. | Still open: `AGENTS.md`, `DESIGN.md`, `DEPLOYMENT.md`, `README.md`, `PROVISIONING.md` restate service names and must point at `NAMING.md` instead. |
| G3 | **No formal grammar.** No charset/length rules (LDH, 63-octet label, 253-octet name), no statement about non-DNS-safe subdomains already in use (`cam.moonraker`, `*.pub.*`), case, or trailing dot. | Add a grammar section + a name validator used by I1/I2. |
| G4 | **No operational DNS policy.** No TTL strategy per plane, no PTR/reverse-zone policy (relevant for mail), no DNSSEC statement. | Add a TTL/PTR/DNSSEC policy section. |
| G5 | **Migration has no verification gates.** §9 lists stages but not how completion is proven. | Add per-stage acceptance checks (record/vhost/redirect diffs, consumer greps). |
| G6 | ~~Host-FQDN rule missing~~ **retracted — my error.** `ARCHITECTURE.md` §3.3 *does* specify it (`*.node.vyrx.de`, CNAME to the overlay address); §2 above invented `<hostname>.<plane>` instead. | §2 now follows §3.3; still open: whether the undeclared `edge`/`ops` labels become aliases or are dropped. |
| G7 | ~~overlay plane naming~~ **closed.** The overlay plane is **`mesh`** (`.mesh.vyrx.de`), matching the contract enum value. `ARCHITECTURE.md` §3 and this document were updated; the enum is unchanged. | — |
