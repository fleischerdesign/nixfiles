# Domain: network

> The network is the domain that *cannot* be reconciled by the plane, and that is the point. This
> document records why, how the control plane coexists with the nftables and mesh model, and what must
> be measured before k3s runs on a host. Touches **R1**, **R8**, **R12**; references decision **D1**
> and baseline B5-B9.

## 1. Stratification (R1)

```
   mesh, WireGuard, addresses, routes        (Nix, my.topology)   ── never reconciled
   firewall, trust zones, forwarding         (Nix, projections)   ── never reconciled
   ───────────────────────────────────────────────────────────────────────────────
   control-plane API reachable over the mesh (a publication like any other)
```

The plane runs **on** the mesh; it cannot manage the mesh without depending on itself. A network fact
is declared in [`../../../contracts/topology/`](../../../contracts/topology/) and projected, never created by
a controller.

## 2. The API as an ordinary endpoint

The control-plane API is reachable on the WireGuard address only. It is declared as a `publication`
with a scope and an auth method, so it flows through the same firewall projection and the same exposure
audit as every other endpoint. Consequences:

- it is not a public listener; the read-only scenario in the audit stays clean;
- it is admitted only from the mesh trust level;
- a second, hand-opened port for the API is a defect (**R12**).

## 3. Coexistence with nftables

The fleet's firewall renders per-table declarations and does not flush foreign tables
([`../../../features/system/networking/`](../../../features/system/networking/)). k3s adds its own
tables (pod network, service rules) and must not disturb ours; the ordering and the no-flush property
are measured before and after k3s start (B6, B7). Service-LB is disabled so no NodePort listener
appears that no contract declared (B8).

## 4. Tenant isolation

Once tenants run workloads, the network is a security boundary inside the plane as well as outside:
namespace network policy isolates tenants, and the firewall continues to treat the whole host as one
scope. The two are complementary: the plane isolates workloads from each other, the Nix firewall
isolates the host from the world.

## 5. The CoreDNS question

k3s runs CoreDNS for the cluster. It must not answer the fleet's own names on the host's resolver
(**D2**/**B9**): the split-horizon story is a naming rule ([naming.md](../../naming.md)), and a cluster DNS
that leaked into it would break it silently.

## 6. Boundary

The network, the mesh and the firewall are Nix, always (**R1**, **migration.md** §7). The plane only
reaches into the network as a consumer. This is what makes the layer removable: removing it leaves the
network exactly as it was.

## 7. Checks

Baseline B5-B9 before k3s and identical after (except for the API's own declared listener); the API is
absent from any public-scope check; a tenant cannot reach another tenant's namespace. See
[checks.md](../checks.md).
