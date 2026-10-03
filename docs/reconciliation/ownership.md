# Ownership

> The ownership matrix is the architecture. The invariants **R3**, **R4**, **R6** and **R10** in
> [model.md](model.md) are the rules; this document is the table those rules produce.

## 1. The rule

> Every resource class has exactly one writer, and within a class every field has exactly one owner.

This is server-side-apply semantics generalised beyond Kubernetes. Ownership is per field, because a
single object often carries both kinds of truth: a `Gateway` object's *image and policy* are declared
(Git-owned), while its *owner identity* and *phase* are observed. A per-object rule would force one of
the two into the wrong home; a per-field rule does not.

Three ownership labels are applied to everything the engine touches:

| Label | Meaning | Reconciled how |
|---|---|---|
| `owner=declared` | Git is the source | enforced: drift is reverted |
| `owner=observed` | an external system is the source | imported: never overwritten |
| `owner=derived` | computed from the two | recomputed on every reconcile |

## 2. The matrix

| Domain | Today | Class | Owner | Mechanism |
|---|---|---|---|---|
| Substrate (OS, boot, kernel) | Nix | declared | repository | Nix (below the line, **R1**) |
| Network, WireGuard mesh, addresses | `my.topology` | declared | repository | Nix |
| Firewall, nftables, trust zones | contract projection | declared | repository | Nix |
| IoT / hardware (ESPHome, Klipper, HA) | Nix | declared | repository | Nix, never reconciled |
| Clients (desktop, notebook) | Home Manager | declared | repository | Nix; consumers, not members |
| External DNS (Cloudflare) | `sync.py` | declared + observed | repository / provider | Flux + provider |
| Internal DNS (Blocky, split horizon) | Nix | declared | repository | Nix - **gap for dynamic names (D2)** |
| TLS / ACME (wildcard, on-demand) | Nix + Cloudflare | declared | repository | Nix - **gating open (D3)** |
| Identity policy (groups, bindings, audience) | blueprints | declared | repository | Crossplane + provider |
| Identity entities (UI users, membership) | UI | observed | Authentik | provider import |
| Secrets, platform | SOPS | declared | repository | Nix + ESO bridge |
| Secrets, entity | - | declared + observed | control plane | control-plane store |
| Storage, platform | `storage` contract | declared | repository | Nix |
| Storage, entity | - | declared | control plane | volumes / PVCs |
| Backup, platform | `backup` contract | declared | repository | restic (Nix) |
| Backup, entity | - | derived | control plane | per-entity backup object |
| Database, platform | `dependencies` contract | declared | repository | PostgreSQL (Nix) |
| Database, tenant | - | derived | control plane | provider-sql / CNPG |
| Telemetry, platform | `telemetry` contract | declared | repository | Prometheus (NixOS) |
| Telemetry, dynamic targets | - | derived | control plane | service discovery - **gap (D4)** |
| Workloads, long-lived | systemd / OpenClaw | declared + observed | control plane | Deployment / CRD |
| Sandboxes, ephemeral | - | declared | control plane | Job + TTL + isolation class |
| External integrations (mail, ntfy) | Nix | declared | repository | Nix |
| Control plane itself | - | declared | repository | Nix seed -> GitOps |
| Control-plane backup / disaster recovery | - | declared | repository + control plane | **gap (D5)** |

Domains marked *gap* are tracked as **D1..Dn** in [edge-cases.md](edge-cases.md). A gap is not a
failure of the model; it is an unresolved decision that must be closed before the domain is moved
across the line.

## 3. Lifecycle and deletion

Invariant **R10**: every class declares what happens to *everything it touched* when the owning
object is removed. The default is not deletion; the default is an explicit choice.

| Strategy | Use | Example |
|---|---|---|
| cascade | derived artifacts with no independent value | a `Gateway`'s Deployment, Service, Ingress |
| orphan | data that outlives its consumer | a tenant database, an archive |
| quarantine | reclaim after a grace period, not immediately | an inactive user's workspace |
| TTL | ephemeral by definition | a sandbox after its last session |

Consequences that must be designed, not discovered: orphaned backup snapshots, orphaned DNS records,
orphaned OIDC clients, orphaned secrets and orphaned volumes. Each is a row in the class's deletion
policy and a drift signal (**R11**) when it survives its owner.

## 4. Secrets

Two stores, one bridge:

- **Platform secrets** stay in SOPS, encrypted in Git, as today.
- **Entity secrets** (an OIDC client secret, a gateway token, a tenant database password) are created
  at run time and live in the control plane's secret store, never in Git.
- **The bridge** is an explicit operator (external-secrets style) that can surface a SOPS value into
  the control plane and a control-plane value back out for a host unit. The bridge is the *only* place
  the two secret systems meet, so the boundary is auditable. A second, silent secret path is a defect.

## 5. Backup

The static path is unchanged (`contracts/backup` -> restic). The dynamic path needs a runtime
counterpart: a derived backup object per entity, carrying the same tier language as the static
contract, with the class's deletion policy applied to its snapshots. A dynamic workload without a
declared backup class is a configuration error, exactly as a host without a backup provider is today.

## 6. Observability

The platform Prometheus runs outside the control plane. It cannot discover dynamic targets through Nix;
it discovers them through the control plane's service discovery (a `ServiceMonitor`-equivalent). A
dynamic workload without a telemetry class is unobservable by construction and must be rejected at
admission (**R12**), not merely unmonitored.
