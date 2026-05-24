# NixOS Configuration

[![CI](https://github.com/fleischerdesign/nixfiles/actions/workflows/ci.yml/badge.svg)](https://github.com/fleischerdesign/nixfiles/actions/workflows/ci.yml)
[![Lint](https://github.com/fleischerdesign/nixfiles/actions/workflows/lint.yml/badge.svg)](https://github.com/fleischerdesign/nixfiles/actions/workflows/lint.yml)

Personal NixOS + Home Manager configuration managed via [Nix Flakes](https://nixos.wiki/wiki/Flakes), spanning 5 hosts.

## Hosts

| Host | Role | Hardware | Purpose |
|------|------|----------|---------|
| `yorke` | notebook | AMD laptop | Daily driver |
| `jello` | desktop | Intel desktop | Gaming / workstation |
| `mackaye` | server | VPS | Central services — Authentik, Grafana, Prometheus, Loki, PostgreSQL, Redis |
| `strummer` | server | Intel home server | Media server — \*arr stack, Jellyfin, Home Assistant, Klipper, Paperless, Authentik outposts |
| `rollins` | server | VPS | Binary cache — Attic server, monitoring exporters, CrowdSec agent |

## Structure

```
.
├── flake.nix              # Entry point: inputs, outputs, 5 systems, deploy config
├── flake.lock
├── lib/
│   ├── helper.nix          # mkSystem, findModules (auto-discovery)
│   └── users.nix           # User metadata & SSH keys
├── roles/                  # Role-based baseline configs
│   ├── pc.nix              # Base PC — audio, wayland, printing, ssh, ...
│   ├── desktop.nix         # Extends pc.nix, sets my.role = "desktop"
│   ├── notebook.nix        # Extends pc.nix, sets my.role = "notebook"
│   └── server.nix          # Headless — no audio/wayland, SOPS host-key decryption
├── features/               # Feature modules (auto-discovered)
│   ├── desktop/            # niri, gnome
│   ├── dev/                # android, containers, codium, nixvim
│   ├── endpoints/          # Service registry — single source of truth for Caddy + Prometheus
│   ├── media/              # gaming, spotify
│   ├── services/           # caddy, authentik, *arr, jellyfin, monitoring, attic, ...
│   │   └── monitoring/     # prometheus, grafana, loki, alloy, exporters
│   └── system/             # common, audio, bootloader, networking, backups, ...
├── hosts/                  # Per-host configuration
│   ├── yorke/              # configuration.nix + hardware
│   ├── jello/              # configuration.nix + hardware
│   ├── mackaye/            # configuration.nix + hardware + disk-config.nix (disko)
│   ├── strummer/           # configuration.nix + hardware
│   └── rollins/            # configuration.nix + hardware + disk-config.nix (disko)
├── user/
│   └── philipp/            # Home Manager config
│       ├── home.nix
│       └── packages.nix    # Role-conditional packages
├── secrets/                # SOPS-encrypted secrets
├── overlays/               # Nixpkgs overlays (openldap fix, docs-conflict fix)
├── media/                  # Wallpaper etc.
├── .github/workflows/      # CI — flake check, build all 5 hosts, lint, daily flake update, dependabot
└── .githooks/              # Pre-commit — nixfmt + deadnix + statix
```

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

Features can also declare dependencies (e.g. enabling `niri` forces `wayland` and `audio`) and conflicts (e.g. `niri` cannot be enabled alongside `gnome`).

### Desktop: niri + Axis Shell

The desktop runs **[niri](https://github.com/YaLTeR/niri)** (scrolling-tiling Wayland compositor) with **[Axis Shell](https://github.com/fleischerdesign/Axis)** as the custom desktop shell. Axis provides the launcher, lock screen, notifications, and quick settings — integrated via D-Bus. **Fish** is the terminal shell, integrated with `direnv` for automatic environment loading. **Ghostty** is the terminal emulator.

### Topology

`features/system/networking/topology` centralizes Tailscale IPs, local IPs, and domains for all hosts. Other features reference peers via `config.my.features.system.networking.topology.hosts.<name>` — no hardcoded IPs.

### Secrets

All secrets are managed via **[SOPS](https://github.com/getsops/sops)** with age encryption — encrypted to the user key, all host SSH keys, and a CI key. Secrets live in `secrets/secrets.yaml`. Each host decrypts them at build time via its own SSH host key, no manual key distribution needed.

## Key Features

### Desktop (yorke, jello)
- **niri** scrolling-tiling Wayland compositor with **Axis Shell**
- **Steam** + **Sunshine** game streaming + **Bottles**
- **Spotify** with Spicetify theming
- **VS Codium** with declarative extensions
- **NixVim** (Neovim configured via Nix) with LSP, Telescope, Treesitter, and German keyboard adaptations
- **Docker** — container runtime (also on strummer)

### Server / Services (mackaye)
- **Authentik** SSO — identity provider (server + LDAP outpost)
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
- **Sonarr** + **Radarr** + **Prowlarr** + **Bazarr** + **SABnzbd** + **Jellyseerr** + **Recyclarr** — full \*arr media stack
- **Jellyfin** — media server with Intel VAAPI hardware decoding
- **Home Assistant** — smart home (Zigbee, ESPHome, MQTT)
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

### Infrastructure (all servers)
- **Distributed monitoring** — Prometheus/Grafana/Loki on mackaye; **node-exporter**, **Grafana Alloy** (log agent), and **blackbox-exporter** run on mackaye, strummer, and rollins
- **Tailscale** VPN — all hosts connected, strummer as subnet router (192.168.178.0/24)
- **Restic** backups — daily encrypted backups with pruning (mackaye, strummer, rollins)
- **NixVim** — terminal editor on all hosts

## Installation / Usage

```bash
# Clone
git clone https://github.com/fleischerdesign/nixfiles && cd nixfiles

# Dev shell (direnv auto-loads nixfmt, deadnix, statix, sops, etc.)
direnv allow

# Build and switch locally
sudo nixos-rebuild switch --flake .#yorke

# Deploy to all hosts via Tailscale
deploy .# -- --ssh-user root -i ~/.ssh/deploy-key

# Edit secrets
sops secrets/secrets.yaml
```

Home Manager is integrated — system builds include user configs, no separate `home-manager switch` needed.

## Tooling

- **Pre-commit hook:** `nixfmt` (format) → `deadnix` (dead code) → `statix` (lint) on staged `.nix` files
- **GitHub Actions:**
  - **CI** — `nix flake check`, builds all 5 hosts, pushes to Attic binary cache, auto-merges update PRs on success
  - **Lint** — `nixfmt` + `deadnix` + `statix` on all `.nix` files
  - **Flake Update** — daily `nix flake update` with auto-PR (merged by CI after validation)
  - **Dependabot** — weekly GitHub Actions dependency updates
- **Formatter:** `nixfmt`
- **Deployment:** `deploy-rs` with auto-rollback
