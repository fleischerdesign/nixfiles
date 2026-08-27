# NixOS Konfiguration

Nix-Flake-basierte NixOS-Konfiguration für 5 Hosts (jello, mackaye, rollins, strummer, yorke) mit Home-Manager-Integration, SOPS-Secret-Management und deploy-rs-Deployment.

## Host-Übersicht

| Host | Rolle | Hardware | Besonderheit |
|---|---|---|---|
| jello | desktop | PC (Intel, NVMe, Intel GPU) | Niri-Desktop |
| yorke | notebook | Laptop (AMD, NVMe) | Niri-Desktop |
| mackaye | server | VPS (QEMU, GRUB/BIOS) | Full-Stack: auth, DB, monitoring master |
| rollins | server | VPS (QEMU, GRUB/BIOS) | Monitoring-Collector, Hermes Agent, Attic Server |
| strummer | server | Bare Metal (Intel, 4TB+1TB disks) | Media-Server (arr-Stack, Jellyfin, Home-Assistant, 3D-Drucker) |

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
│   ├── desktop/{gnome,niri}/       # Desktop Environments (mutual exclusion via assertions)
│   ├── dev/{android,codium,containers,git,nixvim,opencode/}  # opencode/ hat kein default.nix
│   ├── endpoints/                  # my.endpoints — zentrale Service-Registry (kein enable-Flag)
│   ├── media/{gaming,spotify}/
│   ├── services/{35 Features}      # arr-Stack, Monitoring, Auth, DBs, Automation, Media
│   └── system/{14 Features}        # audio, bootloader, common, networking, security, user
├── lib/
│   ├── default.nix         # Public API: { mkSystem } — akzeptiert { home-manager-unstable }
│   ├── helper.nix          # Compatibility-Shim → default.nix
│   ├── features.nix        # { requires } — Feature-Dependency-Manager (mkDefault + assertion)
│   ├── core/
│   │   ├── system-builder.nix  # mkSystem: auto-discovers features + users, baut nixosSystem
│   │   └── module-loader.nix   # findModules: rekursiv alle default.nix unter einem Pfad
│   └── updaters/
│       └── update-custom-packages.sh  # GitHub-Release-Updater für packages/custom/*/manifest.json
├── packages/
│   ├── custom/
│   │   ├── default.nix     # Auto-Discovering Overlay: scannt Subdirectories mit default.nix
│   │   └── <name>/
│   │       ├── default.nix     # callPackage-Derivation
│   │       └── manifest.json   # version, srcHash, upstream-Metadaten (vom Updater verwaltet)
│   └── overlays/fix/
│       ├── bottles/default.nix
│       ├── hermes-agent/default.nix  # Akzeptiert inputs (wird in flake.nix als (import ... inputs) geladen)
│       ├── inline-snapshot/default.nix
│       ├── patool/default.nix
│       └── python314-metadata/default.nix
├── secrets/                # SOPS-verschlüsselte *.yaml — ein Key pro Host
├── .sops.yaml              # Age-Keys: philipp, strummer, mackaye, rls, jello, yorke, ci
├── .githooks/pre-commit
├── .github/
│   ├── workflows/ci.yml    # Push/PR: flake check → Matrix-Build aller 5 Hosts → Attic Push
│   ├── workflows/update.yml # Daily-Cron: flake update + custom-package update → Build → Auto-Commit
│   ├── actions/build-nixos-host/action.yml  # Composite: nix build + attic push pro Host
│   └── dependabot.yml      # Weekly GitHub Actions Updates
├── statix.toml             # disabled = ["repeated_keys"]
└── AGENTS.md               # Diese Datei
```

## Architektur

### Rollen-Vererbungskette

```
base.nix                  # Alle Hosts (common, bootloader, kernel, fish-shell, ssh, security, topology)
├── server.nix            # Server: caddy, monitoring (node-exporter, blackbox-exporter), tailscale, static-ip, nixvim
└── pc.nix                # Desktop/Notebook: audio, wayland, printing, containers, codium, nixvim, gaming, spotify
    ├── desktop.nix       # my.role = "desktop"
    └── notebook.nix      # my.role = "notebook"
```

Rollen setzen **Defaults** (`lib.mkDefault`), Hosts **überschreiben** (`=` ohne mkDefault).

### Feature-System

- **Auto-Discovery**: `lib/core/module-loader.nix` scanned `features/` rekursiv nach `default.nix`. Jedes Feature wird in **jeden** Host geladen.
- **Gating**: Feature-Konfiguration steht hinter `lib.mkIf cfg.enable`. Ein Feature ist geladen, aber nur aktiv wenn `enable = true`.
- **Option-Pfad**: `my.features.<domain>.<feature>` — konsistent mit Verzeichnispfad `features/<domain>/<feature>/default.nix`.
- **Feature-Dependencies**: `features.requires ["services.redis"] config` → setzt `lib.mkDefault true` + assertion (Build bricht ab wenn explizit disabled).
- **Architektur-Prinzipien für Feature-Module**:
  - **Agnostisch & Generisch**: Feature-Module dürfen KEINE hartcodierten User-Namen (`philipp`, `hermes`) oder Host-Namen enthalten. Sie müssen modular, DRY, akademisch sauber und wiederverwendbar sein, sodass auch externe Entwickler sie einbinden können.
  - **System-Features**: Für systemweite Dienste/Hardware (Services, Networking, Drivers). Werden in Host-Configs/Rollen via `my.features.<domain>.<feature>.enable = true` aktiviert.
  - **User-Scoped Features**: Für reine User-Tools (Entwicklungsumgebungen, Shells, Dotfiles, OpenCode). Werden in `features/<domain>/<feature>/default.nix` generisch per `home-manager.sharedModules` bereitgestellt und im jeweiligen User-Kontext (`user/<name>/home.nix` bzw. `opencode.nix`) via `my.features.<domain>.<feature>.enable = true` aktiviert.

**Kanonisches System-Feature-Modul:**
```nix
# features/<domain>/<feature>/default.nix
{ config, lib, pkgs, ... }:
let cfg = config.my.features.<domain>.<feature>;
in {
  options.my.features.<domain>.<feature> = {
    enable = lib.mkEnableOption "description";
    # weitere typed options...
  };
  config = lib.mkIf cfg.enable {
    # NixOS-Konfiguration...
  };
}
```

**Kanonisches User-Scoped Feature-Modul (Home Manager):**
```nix
# features/<domain>/<feature>/default.nix
{ config, lib, pkgs, ... }:
let featureDir = ./.;
in {
  home-manager.sharedModules = [
    ({ config, lib, pkgs, osConfig ? {}, ... }:
    let cfg = config.my.features.<domain>.<feature>;
    in {
      options.my.features.<domain>.<feature> = {
        enable = lib.mkEnableOption "description";
      };
      config = lib.mkIf cfg.enable {
        # Home-Manager Konfiguration für diesen User...
      };
    })
  ];
}
```

**Spezial-Module (nicht im features-Namespace):**
- `features/endpoints/default.nix` → `my.endpoints` (zentrale Service-Registry, kein enable)
- `features/system/user/default.nix` → `my.user` (User-Identity, kein enable)
- `features/system/common/default.nix` → auch `my.role` (Enum: `"server"`, `"desktop"`, `"notebook"`)

**Gegenseitiger Ausschluss:** `desktop/gnome` und `desktop/niri` haben Assertions die den jeweils anderen verbieten.

### Host-Konfigurationsmuster

Jeder Host folgt exakt diesem Muster:
```nix
# hosts/<name>/configuration.nix
{ inputs ? null, config ? null, ... }:     # inputs für Disko, config für Cross-Referenzen
{
  imports = [
    inputs.disko.nixosModules.disko    # Nur VPS-Server
    ./hardware-configuration.nix       # Immer
    ./hardware-specific.nix            # Immer
    ./disk-config.nix                  # Nur VPS-Server mit Disko
    ../../roles/<role>.nix             # Immer
  ];

  networking.hostName = "<name>";

  # Feature-Konfiguration (nicht mkDefault — überschreibt Rolle)
  my.features.<domain>.<feature> = { ... };

  system.stateVersion = "<version>";
}
```

### User-Module

- **metadata.nix** → plain attrset `{ username, fullName, email, sshKeys }` — wird von `features/system/user/default.nix` importiert, füttert `my.user.*` und `users.users.philipp`.
- **home.nix** → `{ pkgs, osConfig, inputs, ... }` — root home-manager module. Verwendet `osConfig.my.role` für Server/Desktop-Gating.
- **osConfig-Bridge**: User-Module lesen NixOS-Konfiguration via `osConfig.my.role`, `osConfig.my.user.name`, `osConfig.my.features.system.networking.topology.*`.
- **Role-Gating-Pattern**: `lib.optionals (role != "server")`, `lib.mkIf (role != "server")` — opencode und 22 Desktop-Pakete nur auf non-Server.

## Nix-Konventionen

- **Formatter**: `nixfmt` (via `nix fmt` oder direkt)
- **LSP**: nil
- **Kein `with`** in Modulen (statix-enforced)
- **`lib.mkIf`** für bedingte Konfiguration, **`lib.mkMerge`** für Komposition
- **Overlays**: Zentral in `flake.nix` → eine `pkgs`-Instanz mit allen Overlays komponiert
- **Fix-Overlays**: `packages/overlays/fix/<name>/default.nix` → manuell in flake.nix registrieren
- **Custom Packages**: `packages/custom/<name>/default.nix` → auto-discovered via `packages/custom/default.nix`
- **Manifest.json**: Version-Metadaten für den Updater (`upstream.type: "github-release"` oder `"github-source"`)

## Secrets (SOPS)

```bash
sops secrets/<name>.yaml    # Editieren
```

Keys in `.sops.yaml` für alle 5 Hosts + CI-Age-Key. `secrets/.*\.yaml$` wird mit allen Host-Keys verschlüsselt.

## CI/CD

**CI (push/PR auf main):**
1. `nix flake check` (eval-hosts + statix + deadnix)
2. Matrix-Build aller 5 Hosts (`nix build .#nixosConfigurations.<host>.config.system.build.toplevel`)
3. Push Result nach Attic Binary Cache (`https://cache.rls.ancoris.ovh`)
4. `fail-fast: false` auf Build-Matrix

**Daily Update (Cron `0 0 * * *`):**
1. `nix flake update` + `nix run .#update-custom-packages`
2. Kompletter Matrix-Build (mit `max-jobs: 1` für Resource-Sparsamkeit)
3. Bei Erfolg: Auto-Commit `chore(deps): update flake inputs and custom packages` auf main

**Dependabot:** Weekly GitHub Actions updates (nicht Nix — nur GHA Ecosystem).

## Deployment

```bash
deploy .#<hostname>     # Remote via deploy-rs über Tailscale SSH
```

SSH-Key: `~/.ssh/deploy-key` (User: `root`). Tailscale-IPs aus `my.features.system.networking.topology.hosts.<name>.tailscaleIp`.

## pi-Integration

Die Pi coding-agent Konfiguration wird als **generisches Feature** in `features/dev/pi/default.nix` deklariert:
- **Architecture**: `features/dev/pi/default.nix` stellt das Feature per `home-manager.sharedModules` bereit und bindet Plugin-Module dynamisch via `lib/plugins.nix` ein.
- **Plugin-System**: Jedes Plugin in `features/dev/pi/plugins/<name>/` folgt dem 3-Dateien-Muster (`manifest.json` für Version/Hashes, `package.nix` für Derivation-Build, `module.nix` für NixOS/Home-Manager Optionen).
- **Auto-Discovery**: `features/dev/pi/lib/plugins.nix` scannt dynamisch nach `package.nix` und `module.nix`, wodurch Plugins ohne manuelle Importlisten geladen werden.
- **Aktivierung**: In den jeweiligen User-Modulen (`user/philipp/pi.nix`) via `my.features.dev.pi.enable = true`.
- **Secrets**: Provider API-Keys werden transparent über `osConfig.sops.templates."pi-auth.json"` als Out-of-Store Symlink verlinkt.

## Custom Package Updater

```bash
nix run .#update-custom-packages [package-name|"all"]
```

Liest `packages/custom/*/manifest.json`, prüft GitHub Releases auf neue Versionen, lädt AppImage herunter, berechnet SRI-Hash, updated manifest. Erfordert `GITHUB_TOKEN` für authentifizierte API-Calls.

