# Domain: exposure

> Reachability and trust for dynamic names: ingress, DNS and TLS. The reusable mechanism already
> exists in the fleet - the OpenClaw publishing wildcard
> ([`../../../features/services/openclaw/gateways.nix`](../../../features/services/openclaw/gateways.nix))
> - so this domain extends a proven pattern rather than inventing one. Owns
> [decisions/0011](../decisions/0011-internal-dns-reconciliation.md); touches **R1**, **R8**, **R12**.
> References decisions **D2**, **D3**.

## 1. Scope

| Concern | Class | Owner | Mechanism |
|---|---|---|---|
| The wildcard publication and its vhost | declared | repository | Nix, applied by Caddy |
| The wildcard certificate (DNS-01) | declared | repository | Nix + Cloudflare |
| External records for dynamic names | derived | reconciler | provider, inside the wildcard |
| The internal (split-horizon) view | derived | reconciler | **D2**, ADR 0011 |
| Per-name TLS for dynamic names | declared | repository | covered by the wildcard (**D3**) |

## 2. The existing pattern, generalized

The fleet already routes a dynamic subdomain inside a statically declared wildcard: a `*.` publication
with `ingressOnly`, a DNS-01 wildcard certificate on the ingress, and a runtime router that maps the
host to the instance. Nothing about that is per-instance in Nix; the per-instance part is data. The
exposure domain reuses exactly this shape, so a dynamic name needs no Nix change, no certificate
change and no external DNS record - only the router's data changes.

## 3. Scopes

A dynamic entity must declare an exposure scope, using the fleet's existing planes:

| Scope | Reachable from | Name |
|---|---|---|
| `public` | the internet, through the ingress | a public name |
| `internal` | the LAN | a `lan.` name |
| `mesh` | the overlay | a `mesh.` name |
| `isolated` | its consumer only | **no name at all** |

`isolated` is the default for anything that does not need a name; a name is a decision, not a
side effect. This is the dynamic counterpart of the exposure plane the fleet already defines.

## 4. DNS and split horizon (D2)

The external record is one half; the internal view is the other, and they must agree per plane. Today
the internal view is Nix-generated; a dynamic name needs it updated at run time. ADR 0011 chooses a
single reconciler for both views so they cannot diverge. A dynamic name that resolves publicly but not
internally - or vice versa - is a failure, checked at both planes.

## 5. TLS (D3)

Issuance stays inside the pre-issued wildcard: no per-name ACME challenge, so no rate-limit pressure
and no on-demand issuance surface. If on-demand issuance is ever enabled, it is gated by an allow-list
(`ask`) so an arbitrary host header cannot trigger a certificate. The certificate is issued at the
ingress, where the name resolves, exactly as today.

## 6. Boundary

The ingress engine and the wildcard remain Nix and platform (**R1**). Dynamic names are data inside the
wildcard. Static serving must not depend on the reconciler (**R8**); if the plane is down, declared
names continue to resolve and serve, and only new dynamic names wait.

## 7. Checks

A dynamic name resolves on both planes; the ingress shows no listener that is not a declared endpoint
(`exposure-audit --strict`); the certificate covers the wildcard and no per-name issuance occurred.
See [checks.md](../checks.md).
