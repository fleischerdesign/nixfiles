# VYRX Infrastructure Architecture Specification

> **Status:** Blueprint / Target State  
> **Primary Domain:** `vyrx.de`  
> **Design Goals:** RFC-Konformität, Zero-Trust Ingress, Entkopplung von Services und Hardware, Kollisionsfreie Subnetze.

---

## 1. Übersicht & Leitprinzipien

Diese Spezifikation definiert die Ziel-Architektur für die vollständige Professionalisierung der Homelab- und Cloud-Infrastruktur. Sie ersetzt das historisch gewachsene System (Hosts nach Punk-Musikern, fragmentierte `.ovh`-Subdomains, Default-Subnetz `192.168.178.0/24`).

### Kernprinzipien:
1. **Service-First statt Host-First:** Dienste haben feste DNS-Endpunkte (`jellyfin.vyrx.de`, `sonarr.lan.vyrx.de`). Sie sind niemals an physische Rechnernamen gekoppelt.
2. **Deterministisches Host-Naming (RFC 1178):** Rechnernamen kodieren Standort, Funktion und Index.
3. **Strikte Trennung von Public & Internal:** Was nicht ins Internet gehört, erhält keine öffentliche Route.
4. **Kollisionsfreie IP-Räume (RFC 1918):** Migration auf `10.10.0.0/16`, um Subnetz-Konflikte bei mobiler Tailscale-Nutzung weltweit auszuschließen.

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
| **`mackaye`** | **`cld-edge-01`** | VPS | QEMU / Public Cloud | Ingress Reverse-Proxy (Caddy), Authentik Core, CrowdSec, Primary DB |
| **`rollins`** | **`cld-ops-01`**  | VPS | QEMU / Public Cloud | Monitoring Pipeline (Prometheus/Grafana), Attic Cache, Hermes Agent |
| **`strummer`**| **`hom-srv-01`**  | Server | Bare Metal (Intel 4TB+1TB) | Storage, Arr-Stack, Jellyfin, Home-Assistant, Klipper, Subnet-Router |
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
         • jellyfin.vyrx.de                    • *.vpn.vyrx.de (Tailscale Mesh)
         • seerr.vyrx.de                       • *.node.vyrx.de (Host Direct Access)
         • cache.vyrx.de
         • hass.vyrx.de
```

### 3.1 Public Zone: `*.vyrx.de`
Geroutet über `cld-edge-01` (Caddy) mit Cloudflare DNS-01 ACME Wildcard-Zertifikat. Authentifizierung via Authentik Proxy/Forward-Auth und CrowdSec Ingress Protection:
- `auth.vyrx.de` ➔ Authentik SSO Portal & IDP
- `jellyfin.vyrx.de` ➔ Jellyfin Media Streaming (gesichert, geroutet via Tailscale zu `hom-srv-01`)
- `seerr.vyrx.de` ➔ Jellyseerr Media Requests
- `cache.vyrx.de` ➔ Attic Nix Binary Cache (geroutet zu `cld-ops-01`)
- `hass.vyrx.de` ➔ Home Assistant Dashboard

### 3.2 Internal Zone: `*.lan.vyrx.de` / `*.vpn.vyrx.de`
Ausschließlich aus dem Heimnetzwerk (`10.10.0.0/16`) oder über das Tailnet erreichbar:
- `sonarr.lan.vyrx.de`
- `radarr.lan.vyrx.de`
- `prowlarr.lan.vyrx.de`
- `sabnzbd.lan.vyrx.de`
- `bazarr.lan.vyrx.de`
- `paperless.lan.vyrx.de`
- `klipper.lan.vyrx.de` (Mainsail & Moonraker)
- `mon.lan.vyrx.de` (Grafana / Alertmanager)

### 3.3 Node Management: `*.node.vyrx.de`
Feste CNAMEs auf die jeweiligen Tailscale-IPs für SSH- und Administrationszugriffe:
- `cld-edge-01.node.vyrx.de`
- `cld-ops-01.node.vyrx.de`
- `hom-srv-01.node.vyrx.de`
- `hom-wrk-01.node.vyrx.de`
- `mob-nb-01.node.vyrx.de`

---

## 4. IP-Netzwerk-Segmentierung (RFC 1918)

Ablösung des Standard-Subnetzes `192.168.178.0/24` durch ein dediziertes Supernet: **`10.10.0.0/16`**.

### 4.1 VLAN / Subnetz-Aufteilung

| Subnetz | VLAN | Name / Zweck | Beschreibung / Richtlinie |
|---|---|---|---|
| `10.10.10.0/24` | 10 | **INFRA / SVR** | Server (`hom-srv-01`), Managed Switches, Access Points, Router |
| `10.10.20.0/24` | 20 | **CORP / WRK** | Vertrauenswürdige Arbeitsgeräte (`hom-wrk-01`, `mob-nb-01`, Smartphones) |
| `10.10.30.0/24` | 30 | **IOT / LAB**  | 3D-Drucker (Klipper), ESPHome, Smart Devices (Isoliert vom Server-LAN) |
| `10.10.99.0/24` | 99 | **GUEST**      | Gäste-WLAN (Reiner Internetzugang, Client-Isolation) |

### 4.2 Feste IP-Adressen (Infrastruktur)

- `10.10.10.1`: Default Gateway / Router
- `10.10.10.10`: `hom-srv-01` (Server Management & Storage)
- `10.10.20.10`: `hom-wrk-01` (Desktop Workstation)
- `10.10.20.100 - 200`: DHCP-Bereich für Clients (`mob-nb-01`, etc.)
- `10.10.30.50`: 3D-Drucker / Klipper

### 4.3 Tailscale Mesh Overlay (RFC 6598)
- Tailscale CGNAT-Bereich: `100.64.0.0/10`
- `hom-srv-01` fungiert als **Subnet Router** und announcet `10.10.0.0/16`.
- Unterwegs ermöglicht Tailscale transparenten Zugriff auf `*.lan.vyrx.de` und `10.10.x.x` ohne Routing-Konflikte.

---

## 5. WLAN SSIDs

- **`VYRX`**: Hauptnetzwerk (VLAN 20 / WPA3-Personal)
- **`VYRX-IOT`**: Smart Home & Hardware (VLAN 30 / 2.4 GHz only / WPA2)
- **`VYRX-GUEST`**: Gäste (VLAN 99 / Isoliert)

---

## 6. NixOS-Codebase Struktur & Migrationsplan

### 6.1 Repo-Refactoring

```
/etc/nixos/
├── flake.nix
├── hosts/
│   ├── cld-edge-01/          <── ex mackaye
│   ├── cld-ops-01/           <── ex rollins
│   ├── hom-srv-01/           <── ex strummer
│   ├── hom-wrk-01/           <── ex jello
│   └── mob-nb-01/            <── ex yorke
├── features/
│   ├── endpoints/            <── Global Service Registry (public / internal)
│   └── system/networking/topology/default.nix
└── .sops.yaml                <── Host-Keys auf neue Namen abbilden
```

### 6.2 Schrittweiser Migrationsplan (Zero-Downtime)

1. **Phase 1: Domain & DNS Setup**
   - Registrierung von `vyrx.de`.
   - Delegierung / DNS-Zone bei Cloudflare anlegen.
   - Wildcard-DNS (`*.vyrx.de`, `*.lan.vyrx.de`) einrichten.
2. **Phase 2: NixOS Topologie & Caddy**
   - Topologie-Modul auf `vyrx.de` vorbereiten.
   - Caddy auf Ingress-Hosts um `vyrx.de` erweitern (alte `.ovh`-Domains temporär als Alias belassen).
3. **Phase 3: Router & Subnetz-Migration**
   - Umstellung des Heimnetz-Routers auf `10.10.10.1/24` (bzw. `10.10.0.0/16`).
   - Statische IPs für `hom-srv-01` (`10.10.10.10`) zuweisen.
   - Tailscale Subnet Router Route aktualisieren.
4. **Phase 4: Host-Renaming & Flake-Update**
   - Git-Branch `refactor/vyrx-architecture` erstellen.
   - Umbenennen der Host-Ordner und `networking.hostName`.
   - SOPS-Keys in `.sops.yaml` aktualisieren und Secrets re-encrypten.
   - Rollout via `deploy .#<target>` über Tailscale.
5. **Phase 5: Decommissioning**
   - Alte `.ancoris.ovh`-Aliase aus Caddy entfernen.
