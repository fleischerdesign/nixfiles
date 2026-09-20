# NixOS configuration — nixfiles 2.0 / VYRX

Declarative NixOS + Home Manager configuration for five hosts, a WireGuard mesh, SOPS-managed secrets,
modular service contracts and agentless reconcilers for the devices that cannot run NixOS.

```bash
git clone <repo> /etc/nixos && cd /etc/nixos
direnv allow                       # nixfmt, deadnix, statix, sops, nod
git config core.hooksPath .githooks # format + lint on every commit
nix flake check                    # every host must evaluate, statix and deadnix must pass
```

Everything else — the architecture, the naming rules, how to deploy, how we work — is in
[`docs/`](docs/README.md). Start with [`docs/architecture.md`](docs/architecture.md); it defines the
vocabulary the other documents use.

| | |
|---|---|
| Hosts, zones, contracts, mesh | [docs/architecture.md](docs/architecture.md) |
| Naming and DNS planes | [docs/naming.md](docs/naming.md) |
| Deploy, verify, recover | [docs/operations.md](docs/operations.md) |
| The engineering bar and the failure patterns | [docs/practices.md](docs/practices.md) |
| Identity and access | [docs/identity.md](docs/identity.md) |
| Security model | [docs/security.md](docs/security.md) |
| Service provisioning | [docs/provisioning.md](docs/provisioning.md) |
| Microcontrollers, access point, router | [docs/embedded.md](docs/embedded.md) |
| Visual identity | [docs/design.md](docs/design.md) |
| Instructions for agentic contributors | [AGENTS.md](AGENTS.md) |

## Quick reference

| Host | Role | Zone | Address | Mesh |
|---|---|---|---|---|
| `cld-edge-01` | server | `mesh` / public | `173.249.22.211` | `10.10.100.1` |
| `cld-ops-01` | server | `mesh` / public | `37.114.55.91` | `10.10.100.2` |
| `hom-srv-01` | server | `infra` | `10.10.10.10` | `10.10.100.10` |
| `hom-wrk-01` | desktop | `corp` | `10.10.20.10` | `10.10.100.20` |
| `mob-nb-01` | notebook | `corp` (roaming) | DHCP | `10.10.100.30` |
