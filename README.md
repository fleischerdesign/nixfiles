# NixOS Configuration

[![CI](https://github.com/fleischerdesign/nixfiles/actions/workflows/ci.yml/badge.svg)](https://github.com/fleischerdesign/nixfiles/actions/workflows/ci.yml)

Personal NixOS + Home Manager configuration managed via [Nix Flakes](https://nixos.wiki/wiki/Flakes), spanning 5 hosts.

## Hosts

| Host | Role | Hardware | Purpose |
|------|------|----------|---------|
| `yorke` | notebook | AMD laptop | Daily driver |
| `jello` | desktop | Intel desktop | Gaming / workstation |
| `mackaye` | server | VPS | Central services — Authentik, Grafana, Prometheus, Loki, PostgreSQL, Redis, Plausible, Vaultwarden |
| `strummer` | server | Intel home server | Media server — \*arr stack, Jellyfin, Home Assistant, Klipper, Paperless, Linkwarden, Homarr |
| `rollins` | server | VPS | Binary cache — Attic server, monitoring exporters, CrowdSec agent |

## Architecture

### Roles

Roles define baseline system features. Each host imports one role:

- **`pc`** — Foundation for graphical machines: PipeWire audio, Wayland, CUPS printing, SSH server, Fish shell, systemd-boot, Firmware.
- **`desktop`** — Extends `pc` with `my.role = "desktop"`.
- **`notebook`** — Extends `pc` with `my.role = "notebook"`.
- **`server`** — Headless baseline: SSH server, SOPS host-key decryption, Fish shell, systemd-boot.

User packages in `user/philipp/packages.nix` are conditional on `my.role`: desktop apps (Ghostty terminal, GIMP, Obsidian, LibreOffice, InkScape, etc.) are only installed when `role != "server"`.

### Features

Features live under `features/<category>/<name>/default.nix` and are **auto-discovered**: `lib/helper.nix` recursively scans every subdirectory for `default.nix` files and includes them as NixOS modules. No manual import needed.

Each feature declares an `my.features.<path>.enable` option. Hosts activate what they need in their `configuration.nix`. Features that aren't enabled have zero effect.

### Desktop: niri + Axis Shell

The desktop runs **[niri](https://github.com/YaLTeR/niri)** (scrolling-tiling Wayland compositor) with **[Axis Shell](https://github.com/fleischerdesign/Axis)** as the custom desktop shell. Axis provides the launcher, lock screen, notifications, and quick settings — integrated via D-Bus. **Fish** is the terminal shell, integrated with `direnv` for automatic environment loading. **Ghostty** is the terminal emulator.

### Topology

`features/system/networking/topology` centralizes Tailscale IPs, local IPs, and domains for all hosts. Other features reference peers via `config.my.features.system.networking.topology.hosts.<name>` — no hardcoded IPs.

### Secrets

All secrets are managed via **[SOPS](https://github.com/getsops/sops)** with age encryption — encrypted to the user key, all host SSH keys, and a CI key. Secrets live in `secrets/secrets.yaml`. Each host decrypts them at build time via its own SSH host key, no manual key distribution needed.

## Key Features & Services

### Desktop (yorke, jello)
- **niri** scrolling-tiling Wayland compositor with **Axis Shell**
- **Steam** + **Sunshine** game streaming + **Bottles**
- **Spotify** with Spicetify theming
- **VS Codium** with declarative extensions
- **NixVim** (Neovim configured via Nix) with LSP, Telescope, Treesitter, and German keyboard adaptations
- **Docker** container runtime

### Server / Services (mackaye)
- **Authentik** SSO — identity provider (server + LDAP outpost)
- **Vaultwarden** — Bitwarden-compatible password manager
- **Plausible** — privacy-friendly web analytics
- **Hermes Agent & WebUI** — AI agent infrastructure and web interface
- **Grafana** + **Prometheus** + **Loki** — monitoring, metrics, and log aggregation
- **CrowdSec** — intrusion prevention (master node)
- **PostgreSQL** + **Redis** — shared databases and caching
- **Caddy** — reverse proxy (mky.ancoris.ovh)
- **CouchDB** — document database sync (Obsidian)
- **ntfy** — push notifications
- **Portfolio** — personal website (fleischer.design)

### Server / Services (strummer)
- **Caddy** — reverse proxy (fls.ancoris.ovh)
- **Authentik** — proxy outpost (forward-auth) + LDAP outpost
- **Homarr** — customizable service dashboard
- **Linkwarden** — bookmark & webpage archiver
- **Sonarr** + **Radarr** + **Prowlarr** + **Bazarr** + **SABnzbd** + **Jellyseerr** + **Recyclarr** — full \*arr media stack
- **Jellyfin** — media server with Intel VAAPI hardware decoding
- **Home Assistant** + **ESPHome** — smart home & Zigbee automation
- **Klipper** + **Moonraker** — 3D printer management
- **Paperless-ngx** — document management with Authentik SSO
- **Mealie** — recipe manager
- **Blocky** — DNS ad-blocker
- **CrowdSec** — intrusion prevention (agent)
- **Cloudflare DDNS** — dynamic DNS updates

### Server / Services (rollins)
- **Attic** — Nix binary cache server (cache.rls.ancoris.ovh)
- **Caddy** — reverse proxy (rls.ancoris.ovh)
- **CrowdSec** — intrusion prevention (agent)

## Developer Tooling & Templates (`tpl`)

The custom Fish function `tpl` bootstraps reproducible Nix flake development environments instantly:

```bash
tpl <template-name> [target-directory]
# Example: tpl rust my-app
```

Available templates are dynamically queried from `github:fleischerdesign/nix-<stack>-template`:
- **Runtimes & Systems:** `bun`, `c`, `cpp`, `deno`, `elixir`, `gleam`, `go`, `haskell`, `java`, `kotlin`, `node`, `ocaml`, `python`, `rust`, `zig`
- **Typesetting:** `typst`

Each template includes pre-configured `flake.nix` (NixOS 26.05), `.envrc` (direnv), starter code files, `.gitignore`, and `nixfmt` formatter.

## Installation & Commands

```bash
# Clone repository
git clone https://github.com/fleischerdesign/nixfiles && cd nixfiles

# Dev shell (direnv auto-loads nixfmt, deadnix, statix, sops, etc.)
direnv allow

# Activate pre-commit hooks
git config core.hooksPath .githooks

# Build and switch locally
sudo nixos-rebuild switch --flake .#yorke

# Deploy to all hosts via Tailscale
deploy .# -- --ssh-user root -i ~/.ssh/deploy-key

# Update custom packages in packages/custom
nix run .#update-custom-packages

# Edit secrets
sops secrets/secrets.yaml
```
