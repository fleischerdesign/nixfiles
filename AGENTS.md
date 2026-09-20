# Working in this repository

Agent-facing instructions. Everything substantive lives in [`docs/`](docs/README.md); this file says
what an agent must know before touching anything, and nothing twice.

## What this is

Declarative NixOS + Home Manager configuration for five hosts, a WireGuard mesh, SOPS secrets, modular
service contracts and agentless reconcilers for devices that cannot run NixOS. The
[architecture](docs/architecture.md) defines the vocabulary - zone, plane, contract, scope, mesh - that
this file uses without redefining.

## Commands

```bash
nix fmt                            # nixfmt over the tree, in place
deadnix --fail                     # no unused code
statix check                       # lint (only repeated_keys disabled, see statix.toml)
nix flake check                    # every host evaluates + statix + deadnix
git config core.hooksPath .githooks # pre-commit runs the three above
nixos-rebuild switch --flake .#<host>            # local
nixos-rebuild switch --flake .#<host> --target-host root@<addr>   # remote
```

A shell here is **fish** locally and on the hosts. `VAR=value cmd`, `$?`, `${PIPESTATUS[0]}` and
`for … do … done` all fail. Wrap anything non-trivial in `bash -c '…'` or `bash -s` with a heredoc,
and prefer a script file over nested quoting - nested quotes have broken more runs in this repository
than any real defect.

## Non-negotiables

1. **Prove the replacement before deleting the original.** Not "it looks right" - a measurement at the
   level the consumer sees. Two outages came from skipping this, one of them taking a host's DNS with
   the service that owned `/etc/resolv.conf`.
2. **A check must be able to fail loudly.** Keep `stderr`, derive the exit code from the checks rather
   than from the last statement, and never end a script on a bare `echo`. A missing tool, a guessed
   file name and a real negative look identical at the point of measurement.
3. **Write the expectation next to the measurement.** It is the only way a number can disagree.
4. **Verify per host class before applying fleet-wide**, and read the tool's *whole* verdict - warnings
   included. A deprecation warning that nobody read cost three rounds of wrong diagnosis.
5. **Documents are specifications of the present.** No migration diaries, no phase plans, no status
   sections - those belong in commit messages. Where a document and the code disagree, the code is
   right and the document is a bug.
6. **English** for code, comments, commits and documentation.
7. **The inventory decides, not the order of a list.** Zones, addresses, names and firewall rules are
   derived from `my.topology` and the contract projections. If you find yourself writing an address or
   a name twice, the derivation is missing.

## Layout

```
flake.nix                 15 inputs, overlays, one mkSystem call per host
hosts/<name>/             entry point: role + hardware + host-specific features
roles/                    base → server | pc → desktop | notebook
features/                 auto-discovered modules, each behind `enable`
  system/  services/  dev/  media/  desktop/
contracts/                provides (interfaces, storage, backup, telemetry), consumes, naming, endpoints
lib/core/                 mkSystem, module auto-discovery
user/<name>/              Home Manager: home.nix, packages, fish, editors
secrets/                  SOPS-encrypted, one file
docs/                     the specification, see docs/README.md
```

## Adding a service

1. `features/services/<name>/default.nix` with an `enable` option.
2. Declare what it offers and needs: `my.contracts.provides.<name>` (endpoints, storage, backup,
   telemetry) and `my.contracts.consumes.<name>`. Caddy vHosts, Authentik blueprints and provider
   resources (databases, users, buckets) are projected from those declarations - never written by hand.
3. Enable it on the host that should run it. Nothing else: names, certificates, firewall rules and
   backup jobs follow from the contracts.

## Hosts

| Host | Role | Zone | Address | Mesh |
|---|---|---|---|---|
| `cld-edge-01` | server | `mesh` / public | `173.249.22.211` | `10.10.100.1` |
| `cld-ops-01` | server | `mesh` / public | `37.114.55.91` | `10.10.100.2` |
| `hom-srv-01` | server | `infra` | `10.10.10.10` | `10.10.100.10` |
| `hom-wrk-01` | desktop | `corp` | `10.10.20.10` | `10.10.100.20` |
| `mob-nb-01` | notebook | `corp` (roaming) | DHCP | `10.10.100.30` |

Reach a host over the mesh (`root@10.10.100.x`, key `~/.ssh/nixfiles-deploy-key`) or - for the cloud
hosts, always available - over their public address. `~/.ssh/deploy-key` is the node tunnel secret and
must never address the fleet. Details in [`docs/operations.md`](docs/operations.md).
