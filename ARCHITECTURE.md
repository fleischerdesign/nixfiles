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
| **`mackaye`** | **`cld-edge-01`** | VPS | QEMU / Public Cloud | Ingress Reverse-Proxy (Caddy), Authentik Core, CrowdSec, Primary DB, Headscale |
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

### 5.1 Headscale: Autarkes Zero-Trust Mesh VPN (Architektur-Erweiterung 1)
- Ablösung des Tailscale SaaS Control Planes durch **Headscale** auf `cld-edge-01`.
- **Volle Datenhoheit:** Alle Routing-Tabellen, Node-Keys und ACLs verbleiben im eigenen System.
- **OIDC-Integration:** Direkte Kopplung an Authentik (`auth.vyrx.de`). Anmeldung am VPN erfolgt nahtlos per Passkey/SSO.

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
- **Kopie 3 (Cold Cloud):** Verschlüsseltes Restic-Offsite-Backup kritischer Daten (Dokumente, Paperless, DB-Dumps) nach S3/B2.

### 5.5 Unified SSO mit Passkeys & WebAuthn (Architektur-Erweiterung 9)
- **Authentik als zentraler IdP:**
  - Vollständige Passwordless-Experience mittels FIDO2 / Passkeys (TouchID / YubiKey / Windows Hello).
  - Native OIDC-Anbindung für: Jellyfin, Grafana, Paperless-ngx, Mealie, Headscale.
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

## 7. Migrations-Phasenplan (Zero-Downtime)

1. **Phase 1: Domain & DNS Setup**
   - Registrierung von `vyrx.de` (z. B. via Cloudflare / Netcup).
   - DNS-Zone bei Cloudflare anlegen (Wildcards `*.vyrx.de`, `*.lan.vyrx.de`).
2. **Phase 2: Ingress & Public Services Transition**
   - Caddy auf `cld-edge-01` für `vyrx.de` konfigurieren (inkl. Let's Encrypt DNS-01).
   - Bestehende `.ovh`-Domains als temporäre CNAMEs/Aliase parallel weiterlaufen lassen.
   - Bereitstellung von `push.vyrx.de` (ntfy) und Passkey-SSO in Authentik.
3. **Phase 3: Router & Subnetz-Migration**
   - Umstellung des Heimnetz-Routers auf `10.10.0.0/16` (VLAN 10/20/30).
   - Statische IP für `hom-srv-01` (`10.10.10.10`) zuweisen.
   - mDNS-Reflector (Avahi) auf `hom-srv-01` aktivieren.
   - Lokales DNS (Blocky) für Split-Horizon konfigurieren.
4. **Phase 4: Headscale & Observability Rollout**
   - Headscale auf `cld-edge-01` etablieren, Hosts migrieren.
   - Vector/Loki Log-Pipeline aufschalten.
5. **Phase 5: Host-Renaming & Codebase-Refactoring**
   - Git-Branch `refactor/vyrx-architecture` anlegen.
   - Umbenennen der Host-Ordner in `hosts/<new-name>/`.
   - `.sops.yaml` Keys migrieren, Secrets re-encrypten.
   - Deployment via `deploy-rs` über das Mesh-VPN.
6. **Phase 6: Decommissioning**
   - Entfernen der alten `.ancoris.ovh`-Aliase aus Caddy.
