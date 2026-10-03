# Security

> The control plane moves a new asset to the top of the value list: the API that can mutate the fleet
> and holds entity secrets. This document is the threat model that invariant **R12** (bounded blast
> radius) exists to enforce. It reuses the fleet's existing exposure model rather than inventing a
> second one.

## 1. Assets

| Asset | Value | Where |
|---|---|---|
| Control-plane API | can create/destroy workloads, read secrets | mesh |
| Entity secret store | run-time credentials | control plane |
| Platform secret store | SOPS | Git + hosts |
| Identity provider (Authentik) | authenticates humans and services | platform |
| Provider/controller images | execute with privileges | control plane |
| The reconciliation engine itself | the fleet's integrity | control plane |

## 2. Trust boundaries

```
  public internet ──ingress──►  platform services (NixOS)
  human ──OIDC──►  Authentik ──authn──►  control-plane API (mesh-only)
  provider ──credential──►  external API (Cloudflare, Authentik, cloud)
  controller ──privileges──►  control plane, actuators
```

The API is never publicly reachable. It is a `publication` with an auth method and a `directAccess`
scope like any other endpoint, so it appears in the firewall projection and the exposure audit - a
second, parallel exposure path is a defect (**R12**).

## 3. Threats and controls

| Threat | Control | Guarded by |
|---|---|---|
| Unauthenticated API access | mesh-only listener, OIDC + RBAC | R12 |
| Over-privileged workload reads another tenant's secrets | namespace RBAC, network policy | R12, D11 |
| Runaway controller provisions unbounded objects | quotas, rate limits, admission | R12, E5 |
| Compromised provider image | Nix-pinned digests, vendored sources, review | R12, E7 |
| Secrets leak into logs, manifests or the store | secret values never rendered; scan on build | testing.md §3 |
| Two writers cause a security field to flap | single-writer per field, admission | R3, R4 |
| Break-glass credential abused | out-of-band storage, rotation on use, audit | D7 |
| Identity outage locks out the operator | break-glass independent of Authentik | D7, bootstrap.md §5 |

## 4. Authentication and authorisation

- **Humans:** OIDC through Authentik; group membership maps to role, roles map to namespaces.
- **Services:** their own credentials; no shared human credential; no long-lived cluster-admin token.
- **Break-glass:** one local administrator, generated at seed, stored outside the plane, rotated on use,
  alerting on use.
- **Least privilege:** a provider gets only the external credential its domain needs; a workload gets
  only its namespace.

## 5. Supply chain

The standing advantage of keeping Nix as the compiler is that images, controllers and providers are
pinned by digest and rebuilt reproducibly. A controller image that is not pinned is refused the same
way an unpinned flake input would be. Provider sources are vendored or referenced by immutable
revision.

## 6. Audit

Every mutation of a declared object is an event with an actor. The audit log is expected to answer, for
any entity: *who created it, why, and what owned it* - for both the declared and the observed half.
An entity whose provenance cannot be answered is a defect, because it means a writer exists that the
ownership model does not know about (**R3**).
