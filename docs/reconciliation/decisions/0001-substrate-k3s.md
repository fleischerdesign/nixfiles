# 0001 - Control-plane substrate: k3s

- **Status:** accepted
- **Date:** 2026-10-03

## Context

The reconciliation layer needs a place to run a generic engine, its providers, and the actuators that
materialize dynamic workloads. That substrate must be installable declaratively by NixOS (invariant
**R1** keeps it below the control plane's own authority), must be reachable only over the WireGuard
mesh, and must be operable by a small team on both a public VPS and a home server.

## Decision

Use **k3s** as the control-plane substrate, as a NixOS service (`services.k3s`), single server first.
Disable the components the fleet already owns: Traefik (Caddy is the edge), the service-LB (no
NodePort listeners that no contract declared), and local-storage.

## Consequences

- One binary, one service, reproducible from the NixOS generation.
- The Kubernetes Resource Model is available without adopting a heavyweight distribution.
- The host firewall and the nftables model keep working, because the fleet's rules use per-table
  declarations and do not flush foreign tables (see `features/system/networking`).
- The control plane is now critical infrastructure: it needs backup (**D5**) and a security model
  (**R12**).
- A single node is a single point of failure for *dynamic* work only; static work is unaffected
  (**R8**).

## Alternatives

- **kcp** - Kubernetes API machinery without pods/nodes. Attractive for a pods-less control plane, but
  a CNCF sandbox with a smaller ecosystem, and the fleet will run pods as actuators anyway. Rejected as
  immature for the primary role; may be revisited for a pods-less segment.
- **A purpose-built reconciler** - smallest dependency, but it re-implements watch, scheduling, RBAC,
  garbage collection and field ownership, which is exactly the unmaintainable path.
- **Full Kubernetes (kubeadm)** - more moving parts for no gain at this scale.
