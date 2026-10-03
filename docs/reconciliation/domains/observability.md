# Domain: observability

> If the layer is not observable it is not operable, and if a dynamic workload is not observable it is
> a defect. This domain makes the reconciliation visible and refuses to create what it cannot see.
> Touches **R11**, **R12**; references decision **D4**.

## 1. Two subjects

| Subject | What is measured | Owner |
|---|---|---|
| The platform (as today) | hosts, static services, uptime | repository (Nix) |
| Dynamic targets | entity workloads, controllers | control plane, discovered at run time |
| The reconciler itself | reconcile latency, errors, drift | control plane |

The platform Prometheus runs outside the plane and is not replaced. Dynamic targets join it through
the control plane's service discovery (**D4**); a second monitoring stack is not built.

## 2. Required telemetry

Telemetry is a required class of every `kind` ([workloads.md](workloads.md) §2). An entity that
registers no target is rejected at admission (**R12**), because an unobservable workload cannot be
operated and its absence would be discovered only during an incident.

## 3. Cardinality and lifetime

Ephemeral targets are the cardinality risk (**E11**). Rules:

- labels are bounded - no unbounded per-instance label values survive the instance;
- a target is dropped as part of the entity's deletion policy (**R10**), so reaping is also cleanup;
- a scrape that cannot be attributed to an owner label is rejected, not stored.

## 4. Drift and audit as observability

The drift signal (**R11**) is a first-class metric and alert, not a log line: divergence between
derived and actual state is exactly the condition an operator must act on. The audit log
([security.md](../security.md) §6) is the second half: for any entity, who created it and what owned
it. Together they answer *what changed* and *who did it* - the two questions an incident asks.

## 5. The plane's own health

Engine readiness, provider health, reconcile queue depth and error rate alert like any other service,
and the plane's own dependencies are part of the platform's monitoring (without forming a cycle:
monitoring is platform, **R1**). A control plane that cannot report its own failure is a single point
of silent failure.

## 6. Boundary

Monitoring stays platform and Nix. Only service discovery and dynamic targets cross the line. If the
plane is down, static monitoring continues and dynamic targets simply go stale - visible, not silent.

## 7. Checks

A dynamic target appears in the platform Prometheus after create and disappears after delete; the drift
alert fires on a deliberate divergence; cardinality stays bounded across a churn cycle. See
[checks.md](../checks.md).
