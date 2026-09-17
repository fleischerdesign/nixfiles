# VYRX Infrastructure Architecture Specification

> **Status:** Blueprint & Architecture Roadmap  
> **Primary Domain:** `vyrx.de`  
> **Design Goals:** RFC-Konformität, Zero-Trust Ingress, Entkopplung von Services und Hardware, Kollisionsfreie Subnetze, Autonomie & Datenschutz.

---

## 1. Übersicht & Leitprinzipien

Diese Spezifikation definiert die Ziel-Architektur für die vollständige Professionalisierung der Homelab- und Cloud-Infrastruktur. Sie ersetzt das historisch gewachsene System (Hosts nach Musikern, fragmentierte `.ovh`-Subdomains, Default-Subnetz `192.168.178.0/24`).

### Kernprinzipien:
1. **Service-First statt Host-First:** Dienste besitzen feste DNS-Endpunkte (`jellyfin.vyrx.de`, `sonarr.lan.vyrx.de`). Sie sind niemals an physische Rechnernamen gekoppelt.
2. **Deterministisches Host-Naming (RFC 1178):** Rechnernamen kodieren Standort, Funktion und Index.
3. **Strikte Trennung von Public & Internal:** Dienste ohne Notwendigkeit für externen Zugriff verbleiben im Zero-Trust-VPN oder lokalen Subnetz.
4. **Kollisionsfreie IP-Räume (RFC 1918):** Migration auf `10.10.0.0/16`, um Subnetz-Konflikte bei mobiler VPN-Nutzung weltweit auszuschließen.
5. **Autarke Datenhoheit & Passwordless Identity:** Self-Hosted SSO (Passkeys/WebAuthn), eigenes Push-Alerting und minimale Abhängigkeiten von Fremd-SaaS.

---

## 2. Host-Taxonomie (Enterprise-Schema)

Schema: **`<location>-<role>-<index>`**

- **Location:**
  - `cld` = Cloud VPS
  - `hom` = Home / On-Premises Bare-Metal
  - `mob` = Mobile Client
- **Role:**
  - `edge` = Ingress Reverse Proxy, Authentik SSO Gateway, Firewall
  - `ops`  = Monitoring Master, Binary Cache (Attic), Deployment Automation
  - `srv`  = Hypervisor, Storage, Media, Home Automation
  - `wrk`  = Workstation Desktop
  - `nb`   = Notebook / Laptop

### Mapping:

| Alter Name | Neuer Hostname | Typ | Hardware / Provider | Primäre Aufgaben |
|---|---|---|---|---|
| **`mackaye`** | **`cld-edge-01`** | VPS | QEMU / Public Cloud | Ingress Reverse-Proxy (Caddy), Authentik Core, CrowdSec, Primary DB, WireGuard Hub |
| **`rollins`** | **`cld-ops-01`**  | VPS | QEMU / Public Cloud | Monitoring Pipeline (Prometheus/Grafana/Loki), Attic Cache, Hermes Agent |
| **`strummer`**| **`hom-srv-01`**  | Server | Bare Metal (Intel 4TB+1TB) | Storage, Arr-Stack, Jellyfin, Home-Assistant, Klipper, Subnet-Router, Blocky |
| **`jello`**   | **`hom-wrk-01`**  | Client | PC (Intel, NVMe, Intel GPU) | Desktop Workstation (Niri) |
| **`yorke`**   | **`mob-nb-01`**   | Client | Laptop (AMD, NVMe) | Mobile Workstation (Niri) |

---

## 3. DNS-Zonen & Routing-Architektur

Alle Services werden unter der Hauptdomain **`vyrx.de`** strukturiert.

```
                                  INTERNET
                                     │
                           ┌─────────▼─────────┐
                           │  *.vyrx.de (Edge) │  (cld-edge-01 / Ingress)
                           └─────────┬─────────┘
                                     │
                    ┌────────────────┴────────────────┐
                    ▼                                 ▼
         Öffentliche Dienste                   Interne Zonen (Zero-Trust)
         • auth.vyrx.de                        • *.lan.vyrx.de (LAN / On-Prem)
         • jellyfin.vyrx.de                    • *.vpn.vyrx.de (Mesh VPN)
         • seerr.vyrx.de                       • *.node.vyrx.de (Host Direct Access)
         • cache.vyrx.de
         • hass.vyrx.de
         • push.vyrx.de (ntfy)
```

### 3.1 Public Zone: `*.vyrx.de`
Geroutet über `cld-edge-01` (Caddy) mit Cloudflare DNS-01 ACME Wildcard-Zertifikat. Authentifizierung via Authentik Proxy/Forward-Auth und CrowdSec Ingress Protection:
- `auth.vyrx.de` ➔ Authentik SSO Portal & IDP (Passkeys / WebAuthn)
- `jellyfin.vyrx.de` ➔ Jellyfin Media Streaming (gesichert, geroutet via VPN zu `hom-srv-01`)
- `seerr.vyrx.de` ➔ Jellyseerr Media Requests
- `cache.vyrx.de` ➔ Attic Nix Binary Cache (geroutet zu `cld-ops-01`)
- `hass.vyrx.de` ➔ Home Assistant Dashboard
- `push.vyrx.de` ➔ Zentrale Push-Benachrichtigungen (ntfy.sh Server)

### 3.2 Internal Zone: `*.lan.vyrx.de` / `*.vpn.vyrx.de`
Ausschließlich aus dem Heimnetzwerk (`10.10.0.0/16`) oder über das Mesh-VPN erreichbar:
- `sonarr.lan.vyrx.de` / `radarr.lan.vyrx.de` / `prowlarr.lan.vyrx.de`
- `sabnzbd.lan.vyrx.de` / `bazarr.lan.vyrx.de`
- `paperless.lan.vyrx.de` / `mealie.lan.vyrx.de`
- `klipper.lan.vyrx.de` (Mainsail & Moonraker)
- `mon.lan.vyrx.de` (Grafana / Alertmanager)

### 3.3 Node Management: `*.node.vyrx.de`
Feste CNAMEs auf die jeweiligen VPN-IPs für SSH- und Administrationszugriffe:
- `cld-edge-01.node.vyrx.de`, `cld-ops-01.node.vyrx.de`, `hom-srv-01.node.vyrx.de`, etc.

---

## 4. IP-Netzwerk-Segmentierung & Smart Home Isolation

Ablösung des Standard-Subnetzes `192.168.178.0/24` durch das kollisionsfreie Supernet **`10.10.0.0/16`**.

### 4.1 VLAN / Subnetz-Aufteilung

| Subnetz | VLAN | Name / Zone | Richtlinie & Firewall |
|---|---|---|---|
| `10.10.10.0/24` | 10 | **INFRA / SVR** | Server (`hom-srv-01`), Managed Switches, Access Points, Router |
| `10.10.20.0/24` | 20 | **CORP / WRK** | Vertrauenswürdige Arbeitsgeräte (`hom-wrk-01`, `mob-nb-01`, Smartphones) |
| `10.10.30.0/24` | 30 | **IOT / LAB**  | 3D-Drucker (Klipper), ESPHome, Smart Devices (Strikt isoliert, kein LAN-Zugriff) |
| `10.10.99.0/24` | 99 | **GUEST**      | Gäste-WLAN (Reiner Internetzugang, Client-Isolation) |

### 4.2 Feste IP-Adressen (Infrastruktur)
- `10.10.10.1`: Default Gateway / Router
- `10.10.10.10`: `hom-srv-01` (Server Management & Storage)
- `10.10.20.10`: `hom-wrk-01` (Desktop Workstation)
- `10.10.20.100 - 200`: DHCP-Bereich für Clients (`mob-nb-01`, etc.)
- `10.10.30.50`: 3D-Drucker / Klipper

### 4.3 IoT-Isolation & mDNS-Reflector (Architektur-Erweiterung 10)
- **Zero-Trust für IoT:** Geräte in VLAN 30 dürfen Verbindungen nur ins Internet aufbauen (sofern nötig) oder Anfragen von `hom-srv-01` (Home Assistant) beantworten. Ein Zugriff von VLAN 30 in VLAN 10/20 wird auf der Firewall blockiert.
- **Avahi / mDNS-Reflector:** `hom-srv-01` agiert als Bridge für Multicast-DNS (`.local`), sodass Streaming (AirPlay, Cast) und Smart-Home-Discovery reibungslos über VLAN-Grenzen hinweg funktionieren, ohne die Netzwerke zu bridgen.

---

## 5. Erweiterte Infrastruktur-Säulen

### 5.1 Natives Kernel-WireGuard Mesh (Stateless & Autark) (Architektur-Erweiterung 1)
- **Vollständig stateless & im Linux-Kernel integriert:** Keine SaaS-Abhängigkeit von Tailscale und kein Single-Point-of-Failure durch fragile Headscale-Control-Planes oder Datenbanken.
- **Topologie & Hub:** `cld-edge-01` fungiert dank fester Public-IP als zentraler WireGuard-Hub und Relay für Roaming-Clients (`mob-nb-01`, Smartphones) und Site-to-Site zu `hom-srv-01`.
- **100% Deklarativ in NixOS:** Keys und Peerings werden über die Topologie-Registry (`my.topology`) verwaltet und ohne externe Auth-Dienste direkt in Kernel-Interfaces konfiguriert.
- **Mobile Integration:** Schlankes On-Demand-Peering für Mobilgeräte via offizielle WireGuard-App (QR-Code-Bootstrap).

### 5.2 Split-Horizon / Dual-Horizon DNS (Architektur-Erweiterung 2)
- Lokaler DNS-Resolver (**Blocky** auf `hom-srv-01`):
  - **Zuhause (VLAN 10/20):** `jellyfin.vyrx.de` oder `hass.vyrx.de` löst direkt lokal auf `10.10.10.10` auf (volle 1 Gbit/s bzw. 2.5 Gbit/s LAN-Performance, keine Latenz, kein Hairpin-NAT).
  - **Unterwegs:** Löst über Cloudflare auf `cld-edge-01` auf und wird verschlüsselt via VPN zu `hom-srv-01` getunnelt.
  - Identische URLs, automatische Performance-Maximierung je nach Aufenthaltsort.

### 5.3 Zentrales Logging & Security-Observability (Architektur-Erweiterung 5)
- **Vollständiger Grafana LGTM-Stack:**
  - **Loki:** Zentraler Log-Aggregator auf `cld-ops-01`.
  - **Vector / Alloy Agent:** Auf allen 5 Hosts installiert. Streamt Systemd-Journals, Caddy-Access-Logs, Sonarr/Radarr-Events und CrowdSec-Auditlogs an Loki.
  - **CrowdSec Ingress Protection:** Auf `cld-edge-01` und `cld-ops-01`. Bösartige IPs werden global gebannt; Alerts fließen in Echtzeit ins Grafana-Dashboard.

### 5.4 3-2-1 Enterprise Backup-Strategie (Architektur-Erweiterung 6)
- **Kopie 1 (Lokal):** Dateisystem-Snapshots (ZFS/Btrfs) auf `hom-srv-01` (Minutentakt, Schutz vor versehentlichem Löschen).
- **Kopie 2 (Offsite im eigenen Netz):** Restic-Backup nächtlich verschlüsselt von `hom-srv-01` via VPN auf `cld-ops-01`.
- **Kopie 3 (Cold Cloud):** Verschlüsselter Restic-Offsite-Backup kritischer Daten (Dokumente, Paperless, DB-Dumps) nach S3/B2.

### 5.5 Unified SSO mit Passkeys & WebAuthn (Architektur-Erweiterung 9)
- **Authentik als zentraler IdP:**
  - Vollständige Passwordless-Experience mittels FIDO2 / Passkeys (TouchID / YubiKey / Windows Hello).
  - Native OIDC-Anbindung für: Jellyfin, Grafana, Paperless-ngx, Mealie.
  - Caddy Forward-Auth Proxy für Anwendungen ohne natives OIDC (Sonarr, Radarr, Prowlarr, Sabnzbd, Bazarr).

### 5.6 Self-Hosted Notification Pipeline mit `ntfy` (Architektur-Erweiterung 12)
- Betrieb eines eigenen **`ntfy.sh`** Servers auf `cld-edge-01` (`push.vyrx.de`).
- **Zentraler Push-Hub für:**
  - **Home Assistant:** Waschmaschine fertig, Alarmanlage, Türkontakt.
  - **Alertmanager / Grafana:** Disks fast voll, Host offline, RAM-Spikes.
  - **CrowdSec:** Erkannte Angriffe / IP-Bans.
  - **Sonarr / Radarr:** Downloads abgeschlossen, Grab-Events.
  - **CI/CD:** GitHub Actions Build- und Test-Fehler.
- Volle E2E-Verschlüsselung, 0 Abhängigkeiten von Firebase/Apple-Push-Tracking.

---

## 6. WLAN SSIDs

- **`VYRX`**: Hauptnetzwerk (VLAN 20 / WPA3-Personal)
- **`VYRX-IOT`**: Smart Home & Hardware (VLAN 30 / 2.4 GHz only / WPA2)
- **`VYRX-GUEST`**: Gäste (VLAN 99 / Isoliert)

---

## 7. Migrations-Phasenplan (Zero-Downtime & Zero-Rework)

1. **Phase 1: Domain Setup & Secrets-Restrukturierung**
   - Registrierung von `vyrx.de` (z. B. via Cloudflare / Netcup) und DNS-Zone anlegen.
   - Refactoring der `secrets/secrets.yaml` in hierarchische Namespaces (Beseitigung von `_mackaye` und Host-Präfixen).
2. **Phase 2: Codebase-Vorbereitung (Endpoints 2.0 & Topologie SSOT)**
   - Einführung von `my.topology` und `my.endpoints` mit Zonen-Support (`public`, `internal`, `mesh`).
   - Caddy auf Ingress-Host so konfigurieren, dass `.vyrx.de` parallel zu bestehenden `.ancoris.ovh`-Aliasen bedient wird.
3. **Phase 3: Router & Subnetz-Migration (Heimnetz)**
   - Umstellung des Heimnetz-Routers auf `10.10.0.0/16` (VLAN 10/20/30/99).
   - Feste IP für `hom-srv-01` (`10.10.10.10`) zuweisen.
   - mDNS-Reflector (Avahi) und lokales DNS (Blocky) für Split-Horizon etablieren.
4. **Phase 4: Host-Renaming & Re-Keying (Sauberer Schnitt)**
   - Git-Branch anlegen und Host-Ordner nach Enterprise-Taxonomie umbenennen (`hosts/<new-name>/`).
   - `.sops.yaml` Age-Key-Namen anpassen und `secrets.yaml` mit neuen Host-Keys re-encrypten.
   - Gezieltes Deployment via `nod switch` (oder `deploy`) über die bestehenden Verbindungs-IPs.
5. **Phase 5: WireGuard Mesh, Observability & Data Lifecycle**
   - Rollout des nativen WireGuard-Meshs mit `cld-edge-01` als Relay-Hub und nativer Node-Taxonomie (`*.node.vyrx.de`).
   - Rollout von Vector/Loki für zentrales Logging und CrowdSec-Mesh.
   - Etablierung der 3-2-1 Restic-Pipeline mit Remote-Tier auf `cld-ops-01`.
6. **Phase 6: Decommissioning**
   - Entfernen aller temporären Legacy-Aliase (`.ancoris.ovh`) und Bereinigung der Alt-Routen.

---

## 8. Codebase & NixOS-Architektur (nixfiles 2.0)

Dieses Kapitel definiert die software-architektonischen Prinzipien, um die Zielinfrastruktur deklarativ, wartungsarm und modular in NixOS abzubilden.

### 8.1 Endpoints 2.0 (Intent-basiertes Service Routing)
Entkopplung von Service-Deklaration und Proxy-/DNS-Implementierung. Ein Service deklariert rein seinen Verwendungszweck (Intent), nicht wie oder wo er geroutet wird.

- **Kanonisches Schema (`my.endpoints.<name>`):**
  - `host`: Ziel-Hostname (z.B. `"hom-srv-01"`). Wandert der Service, ändert sich nur dieses Attribut.
  - `port`: Interner Service-Port.
  - `exposure.scope`:
    - `"public"`: Erreichbar via Edge Ingress (`<name>.vyrx.de`), Let's Encrypt TLS, optional Authentik SSO.
    - `"internal"`: Nur im Heimnetz / VPN (`<name>.lan.vyrx.de`). Kein Public Routing.
    - `"mesh"`: Nur direkte Knoten-Kommunikation über WireGuard.
    - `"isolated"`: Ausschließlich Host-Loopback (`127.0.0.1`).
  - `exposure.auth`: `"none"` | `"authentik"` | `"proxy-pass"`
- **Deklarative Multi-Consumer Ableitung:**
  - **Caddy Engine (`cld-edge-01`):** Filtert alle Endpoints mit `scope = "public"`, baut vollautomatisch Reverse-Proxy VHosts und routet verschlüsselt an die WireGuard IP des Ziel-Hosts.
  - **Blocky DNS Engine (`hom-srv-01`):** 
    - Erzeugt für alle `scope = "internal"` Services lokale Records (`<name>.lan.vyrx.de -> 10.10.10.10`).
    - **Split-Horizon:** Erzeugt für lokale Public-Services (z.B. `jellyfin.vyrx.de`) direkte Rewrites auf das LAN-Interface (`10.10.10.10`), um Latenz und Hairpin-NAT im Heimnetz zu eliminieren.
  - **Firewall Engine:** Berechnet automatisch pro Host die zu öffnenden Ports auf physischen bzw. Mesh-Interfaces.

### 8.2 Secrets 2.0 (Hierarchische Domain-Taxonomie & Host-Agnostik)
Ablösung der flachen Namens-Suppe und Beseitigung aller host-spezifischen Key-Namen (`_mackaye`).

- **Architektur-Garantie:**
  - `defaultSopsFile` verbleibt zentral (kein Aufbrechen in Dutzende Dateien, wodurch 40 Feature-Module angefasst werden müssten).
  - Alle Secrets werden strikt hierarchisch nach Domänen strukturiert:
    ```yaml
    # secrets/secrets.yaml
    infra:
      cloudflare_dns_token: "..."
      attic:
        server_token: "..."
        client_push_token: "..."
    services:
      authentik:
        core_env: "..."
        ldap_outpost_token: "..."
        proxy_outpost_token: "..."
      media:
        sonarr_api_key: "..."
        radarr_api_key: "..."
        sabnzbd_api_key: "..."
      storage:
        restic_env: "..."
        postgres_default_pw: "..."
    observability:
      grafana:
        oidc_client_secret: "..."
        secret_key: "..."
    users:
      philipp:
        password_hash: "..."
        ai:
          openrouter: "..."
          deepseek: "..."
    ```
- **Vorteile:**
  - Keine Host-Bindung: Services können beliebig zwischen Hosts wandern, ohne Secret-Namen zu invalidieren.
  - DRY & Modul-freundlich: Zugriff via `sops.secrets."services/authentik/ldap_outpost_token" = {};`.

### 8.3 Data Lifecycle & Multi-Tier Backup 2.0
Systematischer Ausbau des bestehenden `features/system/backups/restic`-Moduls zu einer deklarativen 3-2-1 Pipeline.

- **Deklarativer Service-Footprint:** Services deklarieren ihre zu sichernden Pfade und Pre-Backup-Hooks (z.B. Postgres-Dumps vor Snapshot-Erstellung).
- **3-Tier Backup-Orchestrierung:**
  - **Tier 1 (Lokal):** Minütliche/stündliche Dateisystem-Snapshots (ZFS/Btrfs) vor Host-Rebuilds.
  - **Tier 2 (Private Mesh):** Nächtlicher Restic-Backup-Push aller Server via WireGuard auf In-Cluster Storage (`cld-ops-01`).
  - **Tier 3 (Offsite Cold):** Verschlüsselter Sync kritischer Nutzdaten (Paperless-Dokumente, Vaultwarden, DB-Dumps) in externen S3/B2-Bucket mit Immutable Retention Lock.

### 8.4 Deklarative Topologie-Registry (SSOT für Zonen & Subnetze)
Zentralisierung aller Netzwerk-Definitionen in `my.topology` zur vollständigen Eliminierung hartcodierter CIDRs und IP-Listen.

- **Single Responsibility:** Die Topologie-Registry ist die alleinige Quelle der Wahrheit für Subnetze, VLANs und Vertrauensstufen:
  ```nix
  my.topology = {
    domain = "vyrx.de";
    subnets = {
      infra = { cidr = "10.10.10.0/24"; vlan = 10; trustLevel = "high"; };
      corp  = { cidr = "10.10.20.0/24"; vlan = 20; trustLevel = "medium"; };
      iot   = { cidr = "10.10.30.0/24"; vlan = 30; trustLevel = "zero"; };
      mesh  = { cidr = "10.10.100.0/24"; vlan = null; trustLevel = "vpn"; };
    };
    hosts = {
      hom-srv-01 = { zone = "infra"; ipv4 = "10.10.10.10"; wireguardIpv4 = "10.10.100.10"; };
      # ...
    };
  };
  ```
- **SOLID / DRY Prinzipien:**
  - Firewall-Regeln und Interface-Bindings greifen typsicher auf die Registry zu.
  - CrowdSec-Whitelists speisen sich automatisch aus allen Subnetzen mit `trustLevel != "zero"`.
  - WireGuard-Peers und AllowedIPs werden deterministisch aus der Topologie generiert ohne manuelle Duplikation.

### 8.5 State- & Persistence-Katalog (Storage Tiering)
Standardisierte Trennung von Zustandstypen in Service-Modulen zur sauberen Koppelung an Speicherpfade und Backup-Strategien.

- **Kategorisierung nach Haltbarkeitsanforderung:**
  - **State (`stateDirs`):** Maschinenlesbare Runtime-Zustände, Datenbanken und Zertifikate (z. B. `/var/lib/postgresql`, `/var/lib/authentik`). Klein, kritisch für Systemfunktion.
  - **Data (`dataDirs`):** Primäre Nutzerinhalte und unersetzliche Nutzdaten (z. B. Dokumente in Paperless, Notizen in Obsidian). Höchste Schutzklasse, Pflicht für Tier 3 Offsite-Backup.
  - **Cache (`cacheDirs`):** Reproduzierbare Zwischendateien, Thumbnails und Transcoding-Puffer (z. B. `/var/cache/*`). Explizit von Backups ausgenommen.
- **Konsistenz:** Service-Module deklarieren diese Pfade einheitlich, sodass Speicherkontingente, Mounts und Backup-Ausschlüsse automatisch abgeleitet werden.

### 8.6 Profile-basiertes Home-Manager Design
Beseitigung des Host-State Leaks (`osConfig.my.role != "server"`) im User-Kontext durch modulare Profil-Komposition.

- **Trennung von Zuständigkeiten:**
  - `user/<name>/profiles/base.nix`: Shell, Git, SSH, Tmux, Basis-CLI (überall aktiv).
  - `user/<name>/profiles/workstation.nix`: GUI-Apps, Ghostty, Codium, Kommunikation, Media (nur aktiv auf `desktop` & `notebook`).
  - `user/<name>/profiles/server.nix`: Headless-Diagnostik, Ops-Tools.
- **Deklaratives Gating im System-Builder:** `lib/core/system-builder.nix` mappt System-Rollen atomar auf User-Profile, ohne dass User-Paketlisten Verzweigungs-Logiken enthalten.

### 8.7 Service-Discovery & Automatische Verdrahtung
Vollständige Entkopplung von abhängigen Diensten (z.B. Authentik Outposts, Web-Clients, Prometheus Scrapes).

- **Intent-basiertes Discovery:** Dienste referenzieren Zielservices über logische Namen (`coreEndpoint = "services.authentik";`), statt hartcodierte IPs und Ports einzubinden.
- **Automatische Auflösung:**
  - Das Modul ermittelt via `my.endpoints.authentik` den zuständigen Host und Port.
  - Die IP wird über `my.topology` aufgelöst (WireGuard-IP für Out-of-Host Verbindungen, `127.0.0.1` für Co-Location).
  - Zieht ein Dienst auf einen anderen Host um, erfolgt das Re-Wiring clusterweit automatisch beim nächsten Build.

### 8.8 Statische Typprüfung & Compile-Time Secret Validierung
Fehlerfrüherkennung bereits bei `nix flake check` / Eval-Zeit statt erst beim Systemstart.

- **Strikte Modul-Assertions:** Typsichere Submodule verhindern ungültige Kombinationen (z. B. `exposure.scope = "public"` ohne `subdomain`).
- **SOPS Schema- & Existenz-Validator:** Flake-Check überprüft deklarativ, ob alle von aktiven Modulen deklarierten `sops.secrets.*`-Pfade tatsächlich in der Secret-Struktur existieren, bevor ein Deployment gestartet wird.

### 8.9 Flake Inputs & Overlay-Hygiene
Minimierung von Closure-Größen, Build-Zeiten und technischen Schulden.

- **Strikte Input-Harmonisierung:** Alle Flake-Inputs müssen zwingend `inputs.nixpkgs.follows = "nixpkgs-unstable"` deklarieren, um doppelte `nixpkgs`-Instanzen und unnötige Paket-Doppelbauten zu eliminieren.
- **Overlay-Lifecycle Policy:** Klare Ausmusterungskriterien für Patches unter `packages/overlays/fix/*`. Sobald Fixes im Upstream-Nixpkgs verfügbar sind, werden Overlays entfernt und veraltete Pinned Packages (z. B. insecure pnpm) bereinigt.
