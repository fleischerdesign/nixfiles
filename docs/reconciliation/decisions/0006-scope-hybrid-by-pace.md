# 0006 - Scope: hybrid by pace

- **Status:** accepted
- **Date:** 2026-10-03

## Context

A control plane can be extended to govern everything, and doing so would replace one mishmash with
another: a slow, single-actor service gains a reconciler, a secret store and a failure domain it does
not need, and the fleet pays operational cost for no reactivity. The reconciliation layer earns its
place only where the pace of change and the number of actors demand it.

## Decision

Adopt the reconciler **only** for domains that are fast-changing and multi-actor - identity, per-owner
workloads, ephemeral sandboxes, tenant data, dynamic names. Everything slow and single-actor stays Nix:
the substrate, the network, the firewall, the mesh, the ingress engine, mail, and the media stack.

## Consequences

- The fleet keeps two clearly separated zones rather than one ambiguous middle (**R7**).
- A domain crossing the line must justify it against a measured churn/actor threshold (**D8**), and
  that justification lives in this package, not in folklore.
- Some domains carry both kinds of state and are split, not moved: identity (policy vs entities), backup
  (platform vs entity), telemetry (platform vs targets).
- Reversible: a domain that does not clear the threshold is simply not moved.

## Alternatives

- **Reconcile everything** - maximal uniformity, maximal operational cost and a larger attack surface;
  rejected for a five-host fleet.
- **Reconcile nothing** - the present blocker; rejected.
- **Reconcile per-host ad hoc** - produces exactly the pattern drift this package exists to end.
