# Security

> **Model:** zero trust, defence in depth · **Secrets:** SOPS with age · **Trust lattice:** the zones of
> [architecture.md](architecture.md) §3, partially ordered
>
> This document states the security model as it is. Where a layer is declared but not yet applied, that
> is said with the measurement, because a security document that describes an intention as a fact is
> worse than no document at all.

## 1. Model

No segment is trusted, including the house LAN. Security is a property of every component, not a wall
at the edge.

**Zero trust (NIST SP 800-207), applied:**

1. **Verify explicitly.** Every access to an internal resource - API, web front end, SSH, metrics -
   carries a cryptographic or identity-based proof: a WireGuard public key, a FIDO2/passkey assertion,
   or an SSH key. There is no "inside, therefore allowed".
2. **Least privilege.** A service account, a process and a person each hold what their task needs and
   nothing else. Service accounts are separate identities from human ones ([identity.md](identity.md)).
3. **Assume breach.** A node may be compromised. Lateral movement is limited by the trust lattice, by
   the fact that the mesh is cryptographically addressed per host, and by keeping credentials narrow.

**Trust lattice.** The zones are partially ordered, and the firewall implements the order rather than
each rule separately:

```
Trust(guest) < Trust(iot) < Trust(mesh) ≤ Trust(corp) < Trust(infra)
```

- *no read up* - `iot` cannot reach an `infra` service;
- *no write down* - no zone initiates uncontrolled writes into a lower one;
- zones are addressing and policy on **one Layer-2 segment**; isolation is enforced by the firewall, not
  by broadcast domains ([architecture.md](architecture.md) §3.1, [naming.md](naming.md)).

## 2. Layers

```
1  Identity & authentication     Authentik, passkeys / FIDO2
2  Ingress & edge                Caddy TLS, CrowdSec IPS, Authentik forward-auth
3  Transport                     WireGuard (ChaCha20-Poly1305), cryptokey routing
4  Operating system              NixOS hardening, systemd sandboxing (see the gap in §4.2)
5  Storage & state               impermanence, restic encryption at rest and in transit
6  Cryptographic material        SOPS / age, per-host and per-user keys
```

## 3. Secrets

SOPS with age, one file (`secrets/secrets.yaml`), keys derived from identities that already exist.

### 3.1 Key hierarchy

| Key | Derived from | Used by |
|---|---|---|
| host key | the host's own `/etc/ssh/ssh_host_ed25519_key`, converted with `ssh-to-age` | every host decrypts its own secrets |
| operator key | the administrator's personal key | break-glass, adding keys |
| deploy keys | generated per purpose, authorised via `deployKeys` in the ssh feature | root access during deployment |

There are no hardware tokens in the current setup: the operator key is a file. That is a deviation from
what this document claimed earlier, and it is stated here rather than left implied.

The Cloudflare API token, the restic passphrase, the WireGuard private keys and the Authentik bootstrap
material all live in that one file. No secret is passed on a command line, embedded in the Nix store, or
written into a generated configuration - the ESPHome engine assembles its `secrets.yaml` in a private
temporary directory and deletes it after the flash.

### 3.2 Losing a device

Deterministic, because the two places that matter are both declared:

```
1  .sops.yaml            remove the lost host's age key
2  sops updatekeys       re-encrypt secrets/secrets.yaml for the remaining recipients
3  my.topology           remove the host's WireGuard public key
4  deploy                all remaining hosts: nixos-rebuild switch --flake .#<host>
   ─────────────────────
   the device keeps no access: no mesh peer, no future secret
```

For a **roaming client** (a phone) whose private key is escrowed under
`infra/wireguard/<name>_private_key`, step 3 revokes the peer, and the escrowed key must be rotated or
deleted in the same change: a lost device that still holds a key is revoked by step 3, but the stale
private half would otherwise remain usable if it ever resurfaced.

Nothing else grants it access, which is the point of deriving peers from the topology instead of
maintaining a peer list.

### 3.3 Missing secrets fail the build

A module that references a secret path which does not exist in `secrets/secrets.yaml` fails
evaluation, not deployment. Same principle as the contract invariants: the build is the place to
discover that something is missing.

## 4. Operating system

### 4.1 Kernel hardening (applied)

`features/system/security/default.nix`, part of the base role on every host:

| Setting | Effect |
|---|---|
| `slab_nomerge` | no merging of slab caches, so a heap overwrite cannot be steered into another cache |
| `page_alloc.shuffle=1` | randomised page allocation against heap spraying |
| `kernel.kptr_restrict = 2` | kernel pointers hidden from unprivileged users |
| `kernel.dmesg_restrict = 1` | `dmesg` readable by root only |
| `kernel.unprivileged_bpf_disabled = 1` | eBPF only for root - the classic sandbox-escape vector |
| `tcp_syncookies = 1` | SYN flood protection |
| `rp_filter = 1` (all, default) | strict reverse-path filtering, anti-spoofing |
| `accept_redirects = 0`, `send_redirects = 0` | no ICMP redirects |

Chosen for **zero runtime cost**: no `init_on_free`, no runtime interceptors, nothing that trades
throughput for a parameter nobody can measure. A build, a database transaction and a transcode run at
native speed.

### 4.2 systemd sandboxing: declared contract, not yet applied

`features/services/*` is expected to sandbox its daemons - `ProtectSystem = "strict"`, `ProtectHome`,
`PrivateTmp`, `PrivateDevices`, `NoNewPrivileges`, `ProtectKernel*`, `RestrictNamespaces`,
`CapabilityBoundingSet = ""` and `AmbientCapabilities = ""`.

**Measured 2026-09-20: none of the 35 service modules sets any of these.** The hardening that exists is
the kernel baseline of §4.1, which comes from the base role and therefore applies everywhere. The
sandboxing layer is a gap, not a claim: until the modules carry the contract, a compromised daemon has
the privileges its unit file gives it, which currently means the defaults.

Enforcing it is a per-service change with a real cost - each one has to be tested, because
`ProtectSystem = "strict"` breaks any service that writes outside its declared state and cache
directories, and the correct fix is to declare those directories rather than to relax the sandbox.

## 5. Network

- **Every host-to-host path is the mesh.** Logs, metrics, backups, Caddy upstreams and the AI gateways
  all run over `wg0` (`10.10.100.0/24`). There is no unencrypted cluster traffic.
- **Cryptographic addressing.** WireGuard binds each overlay address to a public key via `allowedIPs`,
  so IP spoofing inside the mesh is not a possibility to defend against but a configuration error.
- **The ingress is the only public surface.** Caddy terminates TLS, CrowdSec reads its access logs and
  bans offending addresses cluster-wide, Authentik handles authentication. A service that declares
  `scope = "public"` is proxied; one that does not is simply not reachable from outside.
- **Certificates are per name**, issued on the host that terminates it. There is no shared wildcard and
  no copied key material; see [architecture.md](architecture.md) §5.3.

## 6. Access

### 6.1 SSH

- **Two paths, both deliberate.** The cloud hosts accept SSH on their **public address** - measured
  2026-09-20: `cld-edge-01` listens on `173.249.22.211:22` and `10.10.100.1:22`. That public path is the
  lifeline that survives a broken mesh, a bad route or a lockout, and it is why the cloud hosts can be
  repaired when everything else is broken. Every other host listens on its LAN address and its overlay
  address only.
- **Keys only.** `PasswordAuthentication = false`, no root login with a password, Ed25519 keys
  throughout. Two keys are authorised fleet-wide: the operator key (break-glass) and the fleet deploy
  key (`~/.ssh/nixfiles-deploy-key`). `~/.ssh/deploy-key` is the node tunnel secret and never addresses
  a fleet host.
- **sshd binds explicitly.** It binds the addresses that exist on the host, and it waits for the units
  that create them (the mesh interfaces), because sshd reads its `ListenAddress` list once at startup
  and never rebinds.

### 6.2 Deployment

`nixos-rebuild switch --flake .#<host>` locally or with `--target-host`, or `nod switch`. Deployment is
deliberately **not** coupled to health probes: a rebuild must be fast and atomic, and health is observed
asynchronously by the monitoring stack, which alerts independently of who deployed what. A service that
fails after a rebuild shows up as a failed unit and an alert - not as a blocked deploy.

**Verified before a switch, not after:** that the replacement path exists (§1 of
[practices.md](practices.md)). This is not process for its own sake - two outages came from a service
being removed before the thing that replaced it was proven.

## 7. Audit and incident response

- **Logs leave the host.** Journal, Caddy access logs and CrowdSec decisions are shipped to Loki, which
  runs on `cld-edge-01` with the full observability stack; `cld-ops-01` and `hom-srv-01` run collectors.
  A compromised host cannot erase what has already left it. (An earlier version of this document said
  Loki ran on `cld-ops-01` and named a Vector agent that no longer exists; both were wrong.)
- **Failed units are part of the health check.** A backup that fails silently is a backup that does not
  exist - one run was lost to a DNS outage and was found only by reading `systemctl --failed`.

| Incident | Automatic | Manual |
|---|---|---|
| Brute force against the ingress | CrowdSec bans the address in Caddy | review the Grafana security dashboard |
| Lost device | - | the rekeying sequence in §3.2, then deploy |
| Service failed after a rebuild | systemd restart protection | `nixos-rebuild --rollback switch`, or the previous generation from the boot menu |
| Unauthorised SSH attempt | CrowdSec bans the source | alert through the ntfy `security` topic |
| Lost root access to a host | - | [operations.md](operations.md) §8 |
