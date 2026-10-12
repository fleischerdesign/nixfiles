# nixfiles

Declarative NixOS + Home Manager configuration for five hosts: a WireGuard mesh, SOPS-managed
secrets, modular service contracts and agentless reconcilers for the devices that cannot run NixOS.

```bash
git clone <repo> /etc/nixos && cd /etc/nixos
direnv allow                        # nixfmt, deadnix, statix, sops, nod
git config core.hooksPath .githooks # format and lint on every commit
nix flake check                     # every host must evaluate; format, statix and deadnix must pass
```

The specification is [`docs/`](docs/README.md) - start with
[`docs/architecture.md`](docs/architecture.md), which defines the vocabulary the other documents use.
Agent-facing rules live in [`AGENTS.md`](AGENTS.md).
