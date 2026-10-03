# Domain: workloads

> The second domain across the line: the instances that exist because of observed truth. Generalizes
> the current per-owner OpenClaw gateways
> ([`../../../features/services/openclaw/gateways.nix`](../../../features/services/openclaw/gateways.nix)).
> Owns [decisions/0008](../decisions/0008-isolation-classes.md); touches **R3**, **R5**, **R7**,
> **R10**, **R12**. References decisions **D1**, **D11**, **D13**.

## 1. Scope

| Instance | Lifecycle | Source of existence |
|---|---|---|
| Per-owner long-lived (gateway, tenant app) | until revoked | observed membership |
| Ephemeral sandbox (task, session, CI) | TTL | an explicit object or event |
| System workload (a controller) | until upgraded | declared |

## 2. The `kind`

A domain is a `kind`, not a special case. `Gateway` is the working name for the first one; a different
service is a different `kind` or a parameter of the same one, never a new program
([architecture.md](../architecture.md) §3). Each `kind` composes the planes:

- **exposure** - a publication with a scope ([exposure.md](exposure.md));
- **identity** - its owner, from observed membership ([identity.md](identity.md));
- **state** - its volumes ([data.md](data.md));
- **secrets** - its entity credentials ([secrets.md](secrets.md));
- **telemetry** - a required target ([observability.md](observability.md));
- **backup** - a required class ([ownership.md](../ownership.md) §5).

A `kind` that omits one of these is rejected at admission (**R12**), because an unobservable,
unbackupable or unnamed instance is the class of defect this layer exists to prevent.

## 3. Isolation classes

The contract states a requirement, not a technology ([decisions/0008](../decisions/0008-isolation-classes.md)):

| Class | Guarantee | Backend chosen by |
|---|---|---|
| `namespace` | process and network isolation | the engine, always available |
| `kernel` | a stronger syscall boundary | availability on the host |
| `vm` | a separate kernel | measured KVM availability (baseline B1-B3) |

The resolver picks a backend per host from the class and the host's measured capability. A host that
cannot satisfy a class runs no workload of that class - it does not silently downgrade.

## 4. Lifecycle

1. **Create** - derived from observed membership, or an explicit object. No hand-numbered ports: the
   address is a function of the instance identity, as `ports.nix` already derives offsets.
2. **Health** - a readiness probe; a failing instance is not traffic-bearing and alerts.
3. **Inactivity** - a TTL/configurable idle window; expiry reaps, it does not stop silently.
4. **Delete** - the class deletion policy runs to completion; the orphan check is the acceptance test
   (**R10**).

## 5. Resource governance

Quotas per tenant and per `kind` bound the blast radius of a runaway controller (**E5**, **R12**).
Capacity is a scheduling input: ephemeral classes may be over-committed, long-lived classes may not.
A workload that cannot be scheduled is reported, never dropped.

## 6. Boundary

The engine and its controllers are infrastructure; a workload is a consumer. If the layer is removed,
long-lived instances return to the existing systemd/feature mechanism (as OpenClaw gateways do today),
and ephemeral classes simply cease to exist - they have no Nix counterpart by definition.

## 7. Checks

`reconciliation-convergence` (a lost event still yields the instance), the lifecycle end-to-end check
(create, health, TTL, delete, no orphan), and the isolation resolver check (a host is not offered a
class it cannot satisfy). See [checks.md](../checks.md).
