# 0008 - Isolation classes

- **Status:** accepted
- **Date:** 2026-10-03

## Context

Dynamic workloads range from a trusted personal service to a sandbox running user-directed code. A
single isolation strategy is either too weak (containers for untrusted code) or too expensive
(a virtual machine for everything). The substrate's capability is not uniform across the fleet: a
home server has KVM, a small VPS may not (**D1**, baseline B1-B3).

## Decision

A workload declares an **isolation class** - `namespace`, `kernel` or `vm` - and a resolver chooses a
backend per host from the class and the host's *measured* capability. A host is never offered a class it
cannot satisfy; it does not silently downgrade.

## Consequences

- Untrusted, multi-tenant workloads can require `vm` without forcing it on trusted ones.
- Placement follows capability: a `vm` class lands only on hosts with proven KVM.
- The backend is swappable behind the class - the actuator names the class, not the technology.
- Capacity planning must account for the cost of the strongest class actually requested.

## Alternatives

- **Containers only** - one kernel escape compromises the host; unacceptable for agentic workloads.
- **VMs only** - under-dense and needless for trusted services.
- **Per-workload backend choice** - leaks technology into the contract and ends the agnosticism the
  model is built on.
