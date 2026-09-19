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
  `*.vpn.vyrx.de (Mesh VPN)`.
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
   on `hom-srv-01`, but never states who is authoritative for `lan`/`vpn`/`iot` or whether
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
| vpn | `"mesh"` | `vpn.vyrx.de` | Blocky + our overlay DNS | **no** | WireGuard mesh |
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
* `lan`/`vpn`/`iot` exist **only** in Blocky and must never be published (§5.1).
* `vpn` is **our** overlay namespace. Tailscale is transitional and will be removed; the
  `vpn` plane is authoritative in our own DNS — **no MagicDNS dependency**.

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
| `"mesh"` | `vpn.` |
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

| Resolver | `public` name | `lan` / `vpn` / `iot` name |
|---|---|---|
| Cloudflare | ingress public IPv4 | *(NXDOMAIN — not published)* |
| Blocky (local) | provider LAN/overlay IPv4 (split-horizon rewrite) | provider address in that plane |

This is what makes `jellyfin.vyrx.de` resolve to `10.10.10.10` at home and to the ingress
abroad (documented in §5), and it removes the entire `.lan`-duplicate class of aliases such
as `mon.lan.vyrx.de` / `grafana.ops.vyrx.de`.

---

## 5. Wildcards

Wildcards are **part of the design** (see the documented `*.vpn.vyrx.de`). What is *not*
part of the design is a wildcard that encodes a **host** into a **service** namespace.

| Wildcard | Status | Purpose |
|---|---|---|
| `*.${domain}` → ingress | **kept** (exactly one) | catch-all for the public plane; never shadows a projected name |
| `*.vpn.${domain}` | **kept** (documented) | overlay namespace |
| `*.${service}.${domain}` | **kept**, service-declared via `extraDomains` | runtime-minted names (OpenClaw self-publishing `<app>.pub.<inst>.ai.vyrx.de`) |
| `*.edge.${domain}`, `*.ops.${domain}` | **abolished** | these only existed because service names encoded hosts |

A wildcard **certificate** (`*.${domain}`, DNS-01) is recommended for the public plane, with
one caveat: a wildcard cert covers **one** label only, so multi-label dynamic names
(`<app>.pub.<inst>.ai.vyrx.de`) still need their own certificate. OpenClaw already issues
those via Caddy `on_demand_tls` (§8.1 of the code).

### 5.1 The public catch-all conflicts with the internal planes (verified defect)

RFC 4592 resolves wildcards by *closest encloser*, so an apex wildcard `*.${domain}` absorbs
names that merely look like they belong to an internal plane. **Verified live** (Cloudflare
DoH): `foo.lan.vyrx.de`, `bar.vpn.vyrx.de` and `x.iot.vyrx.de` **all resolve to the ingress**.
The internal planes are therefore *not* isolated today, and the obvious-looking claim
"internal planes return NXDOMAIN publicly" is empirically false.

Exactly one of these must be chosen before I4/I5 can be enforced:

* **A — explicit public names, no catch-all.** Publish only intended public names;
everything else is NXDOMAIN. Maximum isolation, at the cost of a new service needing a
record before it is reachable.
* **B — keep the catch-all, delegate the internal planes.** Create `lan`/`vpn`/`iot` NS
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
| I4 | The Cloudflare record set contains only `public`-plane names (no `lan.`/`vpn.`/`iot.` suffix). |
| I5 | The Cloudflare record set contains at most one `*` catch-all, pointing at the ingress, and it must not absorb the internal planes (§5.1). |
| I6 | Every projected record's FQDN lies inside a declared plane suffix. |
| I7 | `scope ∈ { public, internal, mesh, isolated }` — the **existing** contract enum, unmapped (`iot` is not an endpoint scope). |
| I8 | Aliases are enumerated in a deprecation report. |
| I9 | A `public` endpoint with `auth = "none"` must carry an explicit `publicExempt = "<reason>"`. Publishing an unauthenticated service to the internet is a **decision**, never a default. |

Read-only projections for inspection and tests: `my.contracts.projections.fqdns`,
`…hostFqdns`, `…dnsRecords.{public,lan,vpn,iot}`, `…ingressVhosts`.

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

1. **Overlay naming:** `vpn.vyrx.de` is authoritative in our own DNS. **Tailscale is
   transitional and will be removed** — no MagicDNS dependency. *(resolved)*
2. **Public IPv6:** resolved factually — neither `cld-edge-01` nor `cld-ops-01` announces a
   global unicast IPv6 prefix (verified: only `tailscale0` ULA `fd7a::/…` and `wg0` ULA
   `fd10:1000:100::/64`). **No `AAAA` records in the public plane** until a provider prefix
   exists; the `vpn` plane keeps its `fd10::/64` ULA records.
3. **Mail zone** (`MX`, `SPF`, `DKIM`, `DMARC`, `PTR`): still needs an explicit, documented
   place in the apex before mail features grow. *(open)*
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
| G1 | **Unenforced.** The invariants (§7) exist as prose only; nothing fails today when they are violated — which is exactly how the §0.2 drift happened. | Implement I1–I8 in report mode, then as assertions, plus a `nix flake check` test. |
| G2 | **DRY violation.** The naming scheme is restated in `ARCHITECTURE.md`, `AGENTS.md`, `DESIGN.md`, `DEPLOYMENT.md`, `IDENTITY.md`, `README.md`, `PROVISIONING.md` and here — eight places that can drift apart, and §0.1 quotes the parent verbatim instead of referencing it. | One normative source (`NAMING.md`); the other documents reference it and drop their restatements. |
| G3 | **No formal grammar.** No charset/length rules (LDH, 63-octet label, 253-octet name), no statement about non-DNS-safe subdomains already in use (`cam.moonraker`, `*.pub.*`), case, or trailing dot. | Add a grammar section + a name validator used by I1/I2. |
| G4 | **No operational DNS policy.** No TTL strategy per plane, no PTR/reverse-zone policy (relevant for mail), no DNSSEC statement. | Add a TTL/PTR/DNSSEC policy section. |
| G5 | **Migration has no verification gates.** §9 lists stages but not how completion is proven. | Add per-stage acceptance checks (record/vhost/redirect diffs, consumer greps). |
| G6 | ~~Host-FQDN rule missing~~ **retracted — my error.** `ARCHITECTURE.md` §3.3 *does* specify it (`*.node.vyrx.de`, CNAME to the overlay address); §2 above invented `<hostname>.<plane>` instead. | §2 now follows §3.3; still open: whether the undeclared `edge`/`ops` labels become aliases or are dropped. |
| G7 | **`mesh` vs `vpn` naming mismatch.** The contract enum says `mesh`, the zone diagram says `vpn`. Both are now mapped, but the mismatch should be resolved deliberately. | Decide: rename the enum to `vpn`, or the zone to `.mesh`. |
