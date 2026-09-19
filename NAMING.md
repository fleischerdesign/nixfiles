# VYRX — DNS, Host & Service Naming Specification

> **Status:** Normative specification (target state). Supersedes every ad-hoc naming
> convention previously implied by `my.features.services.caddy.baseDomain` and the
> hand-written `my.topology.hosts.<host>.domain` values.
>
> **Applies to:** all DNS projections (Cloudflare, Blocky split-horizon), Caddy
> virtual hosts, Authentik OIDC/forward-auth, monitoring targets, and TLS issuance.
>
> **Companion documents:** `ARCHITECTURE.md` §2 (host taxonomy), `IDENTITY.md` (identity),
> `DEPLOYMENT.md` (rollout).

---

## 1. Scope

This document defines **how every name in the `vyrx.de` namespace is formed, who owns
it, who resolves it, and why it can never collide.** It exists because the previous
model encoded the *serving host* in the service name, which makes every service
migration a rename (DNS + virtual host + OIDC redirect URI + bookmarks). That is not
a cosmetic problem: it produced real drift (`grafana.ops.vyrx.de`, `ai.ops.vyrx.de`,
`mon.lan.vyrx.de`, `push.edge.vyrx.de` vs. documented `push.vyrx.de`).

---

## 2. Principles (normative)

1. **A name encodes function and visibility — never placement.**
   The host that serves a name is a *resolution* detail (record target, proxy backend),
   not part of the name. Moving a service between hosts MUST NOT rename it.
2. **Every name has exactly one owner.** Host names are owned by `my.topology`.
   Service names are owned by exactly one `my.contracts.provides` endpoint.
3. **Derivation over declaration.** FQDNs are computed from typed attributes.
   Hand-written FQDN strings are permitted only in the explicit escape hatches
   defined in §7.
4. **Namespaces are planes (visibility boundaries), not hosts.** A plane determines
   the suffix, the authoritative resolver, and — derived from that — the address family
   published in that plane.
5. **The public zone contains only publicly resolvable names.** Internal planes are
   never published to Cloudflare. This is asserted at evaluation time (§9).
6. **One name, split-horizon resolution.** Publicly exposed services keep a single
   public name; LAN/mesh clients resolve the *same* name to the internal address via
   Blocky. There are no `.lan` duplicates of public names.
7. **Illegal states are unrepresentable.** Duplicate names, public endpoints on
   non-public hosts, and internal names inside the public zone fail evaluation (§9).
8. **Renames are migrations, not edits.** A changed name is introduced additively as
   an alias, consumers are migrated, and only then is the old name removed (§8).

---

## 3. Namespace model

The apex zone is `my.topology.domain` (`vyrx.de`), owned by the **ingress host**.

| Plane | Suffix | Authoritative resolver | Published in Cloudflare | Reachable from |
|---|---|---|---|---|
| `public` | `vyrx.de` (apex) | Cloudflare | **yes** | Internet (via ingress) |
| `lan` | `lan.vyrx.de` | Blocky (split DNS) | **no** | Home LAN |
| `iot` | `iot.vyrx.de` | Blocky (split DNS) | **no** | LAN / IoT segment |
| `mesh` | `mesh.vyrx.de` | Blocky + overlay | **no** | WireGuard mesh / Tailnet |
| `isolated` | — (no name) | — | no | direct address/port only |

Consequences:

* The public zone holds: the apex/service names, the public host names, and exactly
  one catch-all wildcard (§7). Nothing else.
* `lan`/`iot`/`mesh` zones exist **only** in Blocky. They are deliberately **not**
  delegated via NS records, so public resolvers return NXDOMAIN for them — the
  internal namespace is not advertised and cannot leak.
* Because planes are disjoint suffixes, an internal name can never be mistaken for a
  public one, and no RFC 1918 heuristic is needed to decide what may be published.

---

## 4. Host names

### 4.1 Derivation

Hostnames already follow the documented RFC 1178 taxonomy
(`<location>-<role>-<index>`, see `ARCHITECTURE.md` §2). The DNS name is derived
from that hostname — it is no longer hand-written per host:

```
hostFqdn(host) = "${hostname}.${host.plane}.${my.topology.domain}"
```

Examples:

| Hostname | Plane | Derived FQDN |
|---|---|---|
| `cld-edge-01` | `public` | `cld-edge-01.vyrx.de` |
| `cld-ops-01` | `public` | `cld-ops-01.vyrx.de` |
| `hom-srv-01` | `lan` | `hom-srv-01.lan.vyrx.de` |
| `hom-wrk-01` | `lan` | `hom-wrk-01.lan.vyrx.de` |
| `mob-nb-01` | `mesh` | `mob-nb-01.mesh.vyrx.de` |

Why: adding a host requires **one** new inventory entry and **no** invented
abbreviation. Collisions are structurally impossible because RFC 1178 hostnames are
already unique.

### 4.2 Short aliases (explicit, bounded)

The ingress pair keeps short aliases because they are part of the operator interface
(SSH targets, documentation, `nod`):

```nix
my.topology.hosts.cld-edge-01.aliases = [ "edge" ];   # → edge.vyrx.de
my.topology.hosts.cld-ops-01.aliases  = [ "ops"  ];   # → ops.vyrx.de
```

Aliases are CNAMEs into the derived host name, are declared in exactly one place, and
are the **only** sanctioned short host labels. They are not service namespaces (§5).

---

## 5. Service names

### 5.1 Derivation

A service name is derived from the endpoint's `scope` (the plane) and `subdomain`:

```
fqdn(endpoint) =
  if endpoint.scope == "isolated"            then null   # no name; address/port only
  else if endpoint.subdomain == null         then null   # no dedicated name
  else "${endpoint.subdomain}.${suffix(scope)}"
```

where `suffix` is `""` for `public`, `"lan."`, `"iot."`, `"mesh."` for the internal
planes (§3). `endpoint.domain` and `my.features.services.caddy.baseDomain` are
**removed from the naming path entirely**.

Examples:

| Service | Endpoint | Derived FQDN |
|---|---|---|
| Authentik | `scope = "public"; subdomain = "auth"` | `auth.vyrx.de` |
| ntfy | `scope = "public"; subdomain = "push"` | `push.vyrx.de` |
| Attic | `scope = "public"; subdomain = "cache"` | `cache.vyrx.de` |
| SearXNG | `scope = "public"; subdomain = "search"` | `search.vyrx.de` |
| OpenClaw (philipp) | `scope = "public"; subdomain = "philipp.ai"` | `philipp.ai.vyrx.de` |
| Jellyfin | `scope = "lan"; subdomain = "jellyfin"` | `jellyfin.lan.vyrx.de` |
| Klipper/Mainsail | `scope = "lan"; subdomain = "mainsail"` | `mainsail.lan.vyrx.de` |
| Prometheus scrape target | `scope = "isolated"` or `subdomain = null` | — (direct address) |

### 5.2 What changes for the operator

* `push.edge.vyrx.de` → **`push.vyrx.de`** (matches the already-documented name and
  ntfy's own `base-url`).
* `cache.ops.vyrx.de` → **`cache.vyrx.de`** (matches the substituter every host already
  uses conceptually; the URL is the single source of truth in
  `features/system/common/default.nix`).
* `livesync.edge.vyrx.de` / `couchdb.edge.vyrx.de` → **`livesync.vyrx.de`** /
  **`couchdb.vyrx.de`**.
* `grafana.edge.vyrx.de` → **`grafana.vyrx.de`** (and the stale `grafana.ops…` alias
  disappears).
* `mon.lan.vyrx.de` disappears: `grafana.vyrx.de` resolves internally via Blocky for
  LAN clients (§6) — one name, split horizon.
* `ai.ops.vyrx.de` disappears: the OpenClaw family is `<name>.ai.vyrx.de`; the
  `ai.vyrx.de` ingress redirect remains.

### 5.3 Public exposure on non-public hosts

`scope = "public"` means **terminated by the ingress**. Endpoints that are only
reachable on the home LAN or the overlay MUST use `lan` / `mesh` / `iot`. This is
enforced (§9): `scope = "public"` on a host without a public address fails evaluation.
Today's `jellyfin`/`mealie`/`caddy` endpoints on `hom-srv-01` are misclassified as
`public` and will become `lan`.

---

## 6. Resolution model (split horizon)

| Resolver | Planes served | Address published |
|---|---|---|
| Cloudflare (authoritative, public) | `public` | ingress host public IPv4/IPv6 |
| Blocky (authoritative locally) | `lan`, `iot`, `mesh` + **internal overrides of `public`** | LAN IPv4 for `lan`; WireGuard IPv4/ULA for `mesh`; device IPv4 for `iot` |
| WireGuard/Tailscale internal DNS | `mesh` | overlay address |

Rule: a `public` name is resolved by Cloudflare to the **ingress** and internally by
Blocky to the **overlay** address of the serving host. Splitting the horizon on a
single name removes the entire `.lan`-duplicate class of aliases.

---

## 7. Wildcards & escape hatches

1. **Exactly one public catch-all** `*.<domain>` → ingress host. It is the fallback
   for names not explicitly projected; it never shadows a projected name.
2. **Dynamic service names** (minted at runtime, e.g. OpenClaw self-publishing
   `<app>.pub.<instance>.ai.vyrx.de`) are declared by the owning service as an
   `extraDomains` entry containing a wildcard. One declaration → one record. No
   per-host wildcards exist.
3. **Per-host wildcards are abolished.** `*.edge`, `*.ops`, `*.ai` disappear together
   with host-encoded service names.
4. **Explicit FQDN override** (`endpoints.<name>.fqdn`) is the last-resort escape hatch
   for names that legitimately cannot follow the scheme (a third-party domain such as
   `fleischer.design`). Every use must carry a comment explaining why.

---

## 8. Aliases & renames

```nix
my.contracts.provides.<service>.endpoints.<name>.aliases = [ "push.edge" ];
```

An alias is published as a CNAME to the endpoint's derived FQDN in the **same plane**,
and is projected by Caddy, Cloudflare/Blocky and Authentik identically to the canonical
name (same vhost, same OIDC redirect URIs). This makes renames additive and reversible:

1. add the new name (derived) — old and new both resolve and serve,
2. migrate consumers (config, `home.nix`, OIDC redirect URIs, client defaults),
3. verify no consumer uses the old name,
4. remove the alias.

`aliases` are **deprecation debt**: they are allowed to exist, but a periodic check
(§9) reports them.

---

## 9. Invariants (evaluation-time checks)

The following are enforced by `assertions` / `nix flake check`; violations are hard
failures, not warnings:

| # | Invariant |
|---|---|
| I1 | Host FQDNs are unique and derived from unique hostnames. |
| I2 | No two endpoints across the fleet derive the same FQDN (and no alias collides with a canonical name). |
| I3 | `scope = "public"` requires the serving host to have a public address. |
| I4 | The Cloudflare record set contains **no** `lan.`/`iot.`/`mesh.` suffix. |
| I5 | The Cloudflare record set contains at most one `*` catch-all, pointing at the ingress host. |
| I6 | Every projected record's FQDN lies inside a declared plane suffix. |
| I7 | `scope` is one of `public`, `lan`, `iot`, `mesh`, `isolated`. |
| I8 | Each alias is reported (deprecation report) so it cannot be forgotten. |

Read-only projections are exposed for inspection and tests:
`my.contracts.projections.fqdns` (service names), `…hostFqdns`,
`…dnsRecords.{public,lan,iot,mesh}`.

---

## 10. API delta (from today)

| Today | Target | Reason |
|---|---|---|
| `endpoints.<n>.domain` (defaults to `caddy.baseDomain`) | **removed** | placement must not influence the name |
| `my.features.services.caddy.baseDomain` | **removed** | same |
| `my.topology.hosts.<h>.domain` (hand-written) | derived; `aliases` instead | §4 |
| `scope = "internal"` | `scope = "lan"` (+ explicit `iot`/`mesh`) | the scope *is* the plane (#I7) |
| `my.topology.hosts.<h>.zone` (VLAN/trust) | unchanged | orthogonal to DNS planes |
| hardcoded `"<svc>.edge.${domain}"` fallbacks in features | removed | §2.1, §5 |
| per-host wildcards | removed | §7.3 |

`scope` becomes the single, agnostic plane selector: one attribute, no host coupling,
no per-feature knowledge of where the service runs.

---

## 11. Migration plan (staged, reversible)

| Stage | Change | Risk |
|---|---|---|
| 0 | Add this spec, the derived-name **projections** (read-only) and invariants I1–I8 in report-only mode. | none (no behaviour change) |
| 1 | Publish derived names **in addition** to the current ones (aliases in the `aliases` list). | none; every name keeps working |
| 2 | Migrate consumers: Caddy vhosts from the projection, OIDC redirect URIs, Blocky mappings, `home.nix` shortcuts, client defaults, `sops`/docs references. | low; verify per host |
| 3 | Reclassify `public`→`lan` on home services; enable I3 as a hard failure. | medium; caught by eval |
| 4 | Remove legacy names, `caddy.baseDomain`, `endpoints.<n>.domain`, the hardcoded `edge` fallbacks and per-host wildcards; run the Cloudflare projection with `--prune` after verification. | low, once stages 0–3 are green |

Each stage is a separate commit and deployable host-by-host; the ingress host
(Cloudflare + Caddy) goes last so that DNS and TLS never point at a not-yet-served name.

---

## 12. Open decisions

1. **`.mesh.vyrx.de` vs. Tailscale MagicDNS** for overlay names — pick one as
   authoritative to avoid two overlapping overlay namespaces.
2. **Public IPv6** in the `public` plane (`AAAA`) — depends on whether the cloud
   providers announce IPv6.
3. **Mail zone** (`SPF`/`DKIM`/`DMARC`/`MX`, PTR) currently lives implicitly in the
   apex; it needs an explicit, documented place before mail features grow.
