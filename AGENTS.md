# NixOS Konfiguration (nixfiles 2.0 / VYRX Enterprise Architecture)

Nix-Flake-basierte Enterprise-NixOS-Konfiguration für 5 Hosts (`cld-edge-01`, `cld-ops-01`, `hom-srv-01`, `hom-wrk-01`, `mob-nb-01`) mit Home-Manager-Integration, SOPS-Secret-Management, WireGuard-Mesh (`10.10.100.0/24`), RFC 1812 Single-NIC Gateway, Service Contracts und `nod`-Orchestrierung.

## Host-Übersicht (RFC 1178 Enterprise Taxonomy)

| Host | Rolle | Zone / Subnetz | Hardware | Besonderheit |
|---|---|---|---|---|
| `hom-wrk-01` | desktop | `corp` (`10.10.20.10`) | PC (Intel, NVMe, Intel GPU) | Niri-Desktop + Axis Shell, OpenClaw Node |
| `mob-nb-01` | notebook | `corp` (Roaming) | Laptop (AMD, NVMe) | Niri-Desktop + Axis Shell, OpenClaw Node |
| `cld-edge-01` | server | `mesh` / Public (`173.249.22.211`) | VPS (QEMU, GRUB/BIOS) | Ingress Hub: WireGuard Relay, Caddy Edge, Authentik SSO, ntfy (`push.vyrx.de`), DBs |
| `cld-ops-01` | server | `mesh` / Public (`37.114.55.91`) | VPS (QEMU, GRUB/BIOS) | Observability Master: Grafana, Prometheus, Loki, OpenClaw AI Gateway (`:18789`), Attic |
| `hom-srv-01` | server | `infra` (`10.10.10.10`) | Bare Metal (Intel, 4TB+1TB) | Single-NIC Gateway (Kea DHCP, Chrony NTP, Blocky DNS), Media (\*arr, Jellyfin), Home Assistant, Klipper |

### Embedded Devices, IoT-Flotte & GitOps-Targets
- `hom-rt-01` (`10.10.10.1`): AVM FRITZ!Box Uplink-Modem (TR-064 GitOps Target `nodTargets.hom-rt-01`).
- `hom-ap-01` (`10.10.10.20`): TP-Link RE330 Wi-Fi Access Point (`tplinkrouterc6u` GitOps Target `nodTargets.hom-ap-01`, Unified SSID `VYRX`).
- `hom-rly-01` .. `hom-rly-08` (`10.10.30.11` .. `10.10.30.18`): Sonoff Basic ESP8266 Inline-Relais (ESPHome GitOps Targets `nodTargets.hom-rly-01` bis `hom-rly-08`).
- `hom-sns-01` (`10.10.30.25`): ESP32 Wohnzimmer Multi-Sensor (BME280, ESPHome GitOps Target `nodTargets.hom-sns-01`).
- `cloudflare`: Deklarative Cloudflare DNS GitOps Engine (`nodTargets.cloudflare`).

## Identitäts- & Benutzerverwaltung (RBAC)

Deklarative Authentik-Blueprints und User-Identity für alle 5 Haushaltsmitglieder:
- **Philipp**: Administrator & Developer (`wheel`, `networkmanager`, `media`, Vollzugriff)
- **Katja**: Familie & Mediennutzerin (`media-users`, `family`)
- **Lilly**: Familie & Mediennutzerin (`media-users`, `family`)
- **Kai**: Familie & Mediennutzerin (`media-users`, `family`)
- **Rieke**: Familie & Mediennutzerin (`media-users`, `family`, OpenClaw AI Mesh)

## Build, Test, Lint

**Pre-commit (automatisch):**
```bash
git config core.hooksPath .githooks    # einmalig aktivieren
```
Pipeline: `nixfmt` → `deadnix --fail` → `statix check` (auf `.nix`-Dateien). `set -e` — jeder Fehler bricht ab.

**Manuelle Checks:**
```bash
nix flake check                     # eval-hosts (alle 5 Hosts) + statix + deadnix
nix fmt                             # nixfmt auf das gesamte Repo
nixos-rebuild dry-run --flake .#<host>
```

**Reihenfolge nach Code-Änderungen:**
1. `nixfmt <dateien>` — formatiert in-place
2. `deadnix --fail` — entfernt unbenutzten Code
3. `statix check <datei>` — lintet (nur `repeated_keys` disabled)
4. `nix flake check` — validiert alle Hosts evaluieren korrekt

## Projektstruktur

```
/etc/nixos/
├── flake.nix               # 15 Flake-Inputs, Overlay-Liste, mkSystem-Aufruf pro Host
├── flake.lock
├── hosts/<name>/
│   ├── configuration.nix   # Einstiegspunkt: imports role + hardware + host-spezifische Features
│   ├── hardware-configuration.nix  # Generiert oder manuell (VPS: QEMU-Gast)
│   ├── hardware-specific.nix       # Zusätzliche Hardware (Intel GPU, Bluetooth, Extra-Disks, GRUB-Override)
│   └── disk-config.nix     # Nur Server mit Disko (GPT-Partitionierung)
├── roles/
│   ├── base.nix            # Alle Hosts: common, bootloader, kernel, fish-shell, topology, security, ssh
│   ├── pc.nix              # PC/Desktop: audio, wayland, printing, containers, codium, nixvim, gaming, spotify
│   ├── desktop.nix         # my.role = "desktop"
│   ├── notebook.nix        # my.role = "notebook"
│   └── server.nix          # my.role = "server": caddy, monitoring, tailscale, static-ip, nixvim
├── user/philipp/
│   ├── home.nix            # Root: imports sub-module, direnv, Nixcord, home packages
│   ├── metadata.nix        # Statische User-Daten (Name, Email, SSH-Keys) — importiert von features/system/user
│   ├── packages.nix        # Packages (server-gated: desktop-only = 22 extra packages + Ghostty)
│   ├── opencode.nix        # programs.opencode + home.file symlinks (server-gated)
│   └── fish.nix            # Fish-Shell, Aliase, tpl-Funktion (templates bootstrapper)
├── features/
│   ├── contracts/                  # my.contracts.provides — Entkopplung von Services, Endpoints, Storage
│   ├── desktop/{gnome,niri}/       # Desktop Environments (mutual exclusion via assertions)
│   ├── dev/{android,codium,containers,git,nixvim,openclaw,opencode,pi}
│   ├── endpoints/                  # my.endpoints — zentrale Service-Registry (abgeleitet aus contracts)
│   ├── media/{gaming,spotify}/
│   ├── services/{35 Features}      # arr-Stack, Monitoring, Auth, DBs, Automation, Media
│   └── system/{15 Features}        # audio, bootloader, common, gateway, networking, security, theme, user
├── lib/
│   ├── default.nix         # Public API: { mkSystem } — akzeptiert { home-manager-unstable }
│   ├── helper.nix          # Compatibility-Shim → default.nix
│   ├── features.nix        # { requires } — Feature-Dependency-Manager (mkDefault + assertion)
│   └── core/
│       ├── system-builder.nix  # mkSystem: auto-discovers features + users, baut nixosSystem
│       └── module-loader.nix   # findModules: rekursiv alle default.nix unter einem Pfad
├── secrets/                # SOPS-verschlüsselte secrets.yaml
├── .sops.yaml              # Age-Keys für cld-edge-01, cld-ops-01, hom-srv-01, hom-wrk-01, mob-nb-01, philipp, ci
├── .githooks/pre-commit
├── statix.toml             # disabled = ["repeated_keys"]
└── AGENTS.md               # Diese Datei
```

## Architektur

### Rollen-Vererbungskette

```
base.nix                  # Alle Hosts (common, bootloader, kernel, fish-shell, ssh, security, topology)
├── server.nix            # Server: caddy, monitoring, static-ip, nixvim
└── pc.nix                # Desktop/Notebook: audio, wayland, printing, containers, codium, nixvim, gaming, spotify
    ├── desktop.nix       # my.role = "desktop"
    └── notebook.nix      # my.role = "notebook"
```

### Feature-System & Service Contracts

- **Auto-Discovery**: `lib/core/module-loader.nix` scanned `features/` rekursiv nach `default.nix`. Jedes Feature wird in **jeden** Host geladen.
- **Gating**: Feature-Konfiguration steht hinter `lib.mkIf cfg.enable`. Ein Feature ist geladen, aber nur aktiv wenn `enable = true`.
- **Service Contracts (`my.contracts.provides.<name>`)**:
  Services deklarieren rein passiv und host-agnostisch ihre Schnittstellen (`endpoints`) und Persistenzbedarfe (`storage.stateDirs`, `storage.dataDirs`, `storage.cacheDirs`).
  Projektionen nach Caddy-vHosts, Firewall-Rules und Prometheus-Scrapes erfolgen automatisch und strikt entkoppelt über `features/contracts/default.nix`.
- **Single-NIC Gateway & RFC 1812**:
  `features/system/networking/gateway` bündelt Kea DHCPv4, Chrony NTP und IPv4 Forwarding/NAT auf `hom-srv-01`, gespeist aus `my.topology`.

## Deployment

```bash
nod switch <host>       # Direktes Deployment via nod CLI über verifizierte IP / Mesh
```

SSH-Key: `~/.ssh/deploy-key` (User: `root`).
