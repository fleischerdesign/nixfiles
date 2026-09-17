# VYRX Infrastructure Architecture Specification

> **Status:** Blueprint & Architecture Roadmap  
> **Primary Domain:** `vyrx.de`  
> **Design Goals:** RFC-Konformität, Zero-Trust Ingress, Entkopplung von Services und Hardware, Kollisionsfreie Subnetze, Autonomie & Datenschutz, Clean Architecture & SOLID by Design.

---

## 1. Übersicht & Leitprinzipien

Diese Spezifikation definiert die Ziel-Architektur für die vollständige Professionalisierung der Homelab- und Cloud-Infrastruktur. Sie ersetzt das historisch gewachsene System (Hosts nach Musikern, fragmentierte `.ovh`-Subdomains, Default-Subnetz `192.168.178.0/24`).

### Kernprinzipien:
1. **Service-First statt Host-First:** Dienste besitzen feste DNS-Endpunkte (`jellyfin.vyrx.de`, `sonarr.lan.vyrx.de`). Sie sind niemals an physische Rechnernamen gekoppelt.
2. **Deterministisches Host-Naming (RFC 1178):** Rechnernamen kodieren Standort, Funktion und Index (`<location>-<role>-<index>`).
3. **Strikte Trennung von Public & Internal:** Dienste ohne Notwendigkeit für externen Zugriff verbleiben im Zero-Trust-VPN oder lokalen Subnetz.
4. **Kollisionsfreie IP-Räume (RFC 1918):** Migration auf `10.10.0.0/16`, um Subnetz-Konflikte bei mobiler VPN-Nutzung weltweit auszuschließen.
5. **Autarke Datenhoheit & Passwordless Identity:** Self-Hosted SSO (Passkeys/WebAuthn), eigenes Push-Alerting und minimale Abhängigkeiten von Fremd-SaaS.
6. **Clean Architecture & SOLID by Design:** Service-Module sind strikt agnostisch (keine hardcodierten Host- oder User-Namen). Entkopplung über abstrakte Service-Contracts, Inversion of Control und compile-time Projektionen.
7. **Deterministische Zustandslosigkeit (Impermanence):** Ephemeres Root-Dateisystem (`tmpfs` oder Snapshot-Rollback) gekoppelt an standardisiertes Storage-Tiering (State, Data, Cache).

---

## 2. Host-Taxonomie (Enterprise-Schema)

Schema: **`<location>-<role>-<index>`**

- **Location:**
  - `cld` = Cloud VPS
  - `hom` = Home / On-Premises Bare-Metal
  - `mob` = Mobile Client
- **Role:**
  - `edge` = Ingress Reverse Proxy, Authentik SSO Gateway, Firewall, WireGuard Hub
  - `ops`  = Monitoring Master, Binary Cache (Attic), Deployment Automation, AI Gateway
  - `srv`  = Hypervisor, Storage, Media, Home Automation, Local Ingress
  - `wrk`  = Workstation Desktop
  - `nb`   = Notebook / Laptop
  - `ap`   = Access Point (OpenWrt / Wi-Fi Bridge)
  - `rt`   = Router / WAN Gateway (AVM FRITZ!Box)

### Mapping:

| Alter Name | Neuer Hostname | Typ | Hardware / Provider | Primäre Aufgaben |
|---|---|---|---|---|
| **`mackaye`** | **`cld-edge-01`** | VPS | QEMU / Public Cloud | Ingress Reverse-Proxy (Caddy), Authentik Core, CrowdSec Master, Primary DB, WireGuard Hub |
| **`rollins`** | **`cld-ops-01`**  | VPS | QEMU / Public Cloud | Monitoring Pipeline (Prometheus/Grafana/Loki), Attic Cache, Hermes Agent, OpenClaw Gateway |
| **`strummer`**| **`hom-srv-01`**  | Server | Bare Metal (Intel 4TB+1TB) | Storage, Arr-Stack, Jellyfin, Home-Assistant, Klipper, Subnet-Router, Blocky, Local Ingress Caddy |
| **`jello`**   | **`hom-wrk-01`**  | Client | PC (Intel, NVMe, Intel GPU) | Desktop Workstation (Niri), OpenClaw Node |
| **`yorke`**   | **`mob-nb-01`**   | Client | Laptop (AMD, NVMe) | Mobile Workstation (Niri), OpenClaw Node |
| **`-`**       | **`hom-ap-01`**   | Embedded | TP-Link (OpenWrt) | Wi-Fi Bridge (SSIDs: VYRX, VYRX-IOT), Agentless GitOps via nod switch |
| **`-`**       | **`hom-rt-01`**   | Embedded | AVM FRITZ!Box | Uplink Gateway / DSL-Modem, Agentless GitOps (TR-064 API) via nod switch |

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
- `10.10.10.1`: Default Gateway / Router (FRITZ!Box Uplink)
- `10.10.10.10`: `hom-srv-01` (Core Server, Gateway & Storage)
- `10.10.10.20`: `hom-ap-01` (OpenWrt Wi-Fi Access Point)
- `10.10.20.10`: `hom-wrk-01` (Desktop Workstation)
- `10.10.20.100 - 200`: DHCP-Bereich für Clients (`mob-nb-01`, etc.)
- `10.10.30.50`: 3D-Drucker / Klipper

### 4.3 IoT-Isolation & mDNS-Reflector
- **Zero-Trust für IoT:** Geräte in VLAN 30 dürfen Verbindungen nur ins Internet aufbauen (sofern nötig) oder Anfragen von `hom-srv-01` (Home Assistant) beantworten. Ein Zugriff von VLAN 30 in VLAN 10/20 wird auf der Firewall blockiert.
- **Avahi / mDNS-Reflector:** `hom-srv-01` agiert als Bridge für Multicast-DNS (`.local`), sodass Streaming (AirPlay, Cast) und Smart-Home-Discovery reibungslos über VLAN-Grenzen hinweg funktionieren, ohne die Netzwerke zu bridgen.

### 4.4 Single-NIC Gateway & „Dumb Hardware, Smart Server“ (RFC 1812)
- **„Dumb Hardware, Smart Server“-Axiom:**
  - FRITZ!Box und Wi-Fi Access Points (TP-Link) werden zu reinen, transparenten Layer-1/2-Durchleitern (Bridges) degradiert.
  - Sämtliche Netzwerk-Dienste (DHCP, DNS, NTP, Routing, Firewall) werden vollständig aus den Router-/AP-Web-UIs entfernt und zentral auf `hom-srv-01` in NixOS deklariert.
- **Zentrale Dienste auf `hom-srv-01` (`features/system/networking/gateway`):**
  - **DHCP-Server (Kea / Dnsmasq):** IP-Vergabe und MAC-Reservierungen speisen sich zu 100% deklarativ aus `my.topology.devices`.
  - **DNS-Server (Blocky):** Lokale Namensauflösung (`*.lan.vyrx.de`), Split-Horizon und Ad-Blocking.
  - **NTP-Zeitserver (Chrony):** Autarke Zeit-Verteilung für ESPHome, Klipper und Clients ohne externe WAN-Hits.
  - **Layer-3 Gateway & Firewall (nftables):** Single-NIC Router-on-a-Stick leitet Pakete zwischen Subnetzen und Internet-Uplink.
- **0 € Hardware-Zusatzkosten & SOLID-Entkopplung:**
  - Keine neuen Router oder Switches nötig; bestehende Kabel und Hardware werden optimal ausgenutzt.
  - Die Routing- und Firewall-Logik ist vollständig von der Hardware entkoppelt (Dependency Inversion). Zusätzliche Netzwerkkarten oder Managed Switches können später nahtlos ohne Code-Refactoring ergänzt werden.

---

## 5. Erweiterte Infrastruktur-Säulen

### 5.1 Natives Kernel-WireGuard Mesh (Stateless, Autark & Anti-Hairpinning)
- **Vollständig stateless & im Linux-Kernel integriert:** Keine SaaS-Abhängigkeit von Tailscale und kein Single-Point-of-Failure durch fragile Headscale-Control-Planes oder Datenbanken.
- **Topologie & Hub:** `cld-edge-01` fungiert dank fester Public-IP als zentraler WireGuard-Hub und Relay für Roaming-Clients (`mob-nb-01`, Smartphones) und Site-to-Site zu `hom-srv-01`.
- **Zonen-Affines Routing (Anti-Hairpinning):** Ko-lokierte Knoten im selben lokalen Subnetz (`hom-wrk-01` und `hom-srv-01`) kommunizieren direkt über ihre LAN-Interfaces (`10.10.x.x`) mit voller Switch-Line-Speed (1 Gbit/s / 2.5 Gbit/s). Der WireGuard-Hub im Cloud-Rechenzentrum wird strikt nur für standortübergreifenden Verkehr genutzt.
- **TCP-MSS-Clamping & MTU-Garantie:** Deterministische nftables/iptables-Regeln klemmen MSS auf den WireGuard-Interfaces (`clamp-mss-to-pmtu`), um hängende TCP-Handshakes und Paketverlust über mobile DSL/LTE-Uplinks auszuschließen.
- **100% Deklarativ in NixOS:** Private Keys werden via SOPS injiziert, Public Keys und Peerings deterministisch aus `my.topology` abgeleitet.

### 5.2 Split-Horizon / Dual-Horizon DNS & Lokales Ingress
- Lokaler DNS-Resolver (**Blocky** auf `hom-srv-01`):
  - **Zuhause (VLAN 10/20):** `jellyfin.vyrx.de` oder `hass.vyrx.de` löst direkt lokal auf `10.10.10.10` auf (volle LAN-Performance, keine Latenz, kein Hairpin-NAT).
  - **Unterwegs:** Löst über Cloudflare auf `cld-edge-01` auf und wird verschlüsselt via VPN zu `hom-srv-01` getunnelt.
- **Lokaler Ingress Caddy mit Cloudflare DNS-01 ACME:**
  - `hom-srv-01` betreibt einen lokalen Caddy-Ingress. Mittels Cloudflare DNS-01 API bezieht er gültige Let's Encrypt Wildcard-Zertifikate für `*.vyrx.de` und `*.lan.vyrx.de`.
  - **Zero Port-Forwarding:** Es müssen keinerlei Ports (80/443) auf dem Heimrouter geöffnet werden. Volle TLS-Validität ohne Browser-Zertifikatswarnungen.
- **DNS High-Availability (Tiered Fallback):**
  - Router DHCP propagiert Primary DNS: `10.10.10.10` (`hom-srv-01` mit Blocky & Ad-Blocking).
  - Fallback DNS: Router Gateway (`10.10.10.1`) mit Upstream Quad9/Cloudflare – garantiert ununterbrochenen Internetzugriff im Heimnetz bei Server-Wartungsarbeiten.

### 5.3 Zentrales Logging & Security-Observability
- **Vollständiger Grafana LGTM-Stack:**
  - **Loki:** Zentraler Log-Aggregator auf `cld-ops-01`.
  - **Vector / Alloy Agent:** Auf allen Hosts installiert. Streamt Systemd-Journals, Caddy-Access-Logs, Arr-Stack-Events und CrowdSec-Auditlogs an Loki.
  - **CrowdSec Ingress Protection:** Auf `cld-edge-01` und `cld-ops-01`. Bösartige IPs werden global gebannt; Alerts fließen in Echtzeit ins Grafana-Dashboard.

### 5.4 3-2-1 Enterprise Backup-Strategie & Disko-Modernisierung
- **Disko Btrfs-Architektur für `hom-srv-01`:** Ablösung von ext4 auf `hom-srv-01` durch ein deklaratives Disko-Layout mit Btrfs-Subvolumes (`@root`, `@state`, `@data`, `@snapshots`).
- **Kopie 1 (Lokal):** Atomare Dateisystem-Snapshots (Btrfs) auf `hom-srv-01` (Stundentakt / vor System-Rebuilds via `btrbk`/`sanoid`).
- **Kopie 2 (Offsite im eigenen Netz):** Restic-Backup nächtlich verschlüsselt von `hom-srv-01` via WireGuard auf `cld-ops-01`.
- **Kopie 3 (Cold Cloud):** Verschlüsselter Restic-Offsite-Backup kritischer Daten (Dokumente, Paperless, DB-Dumps) nach S3/B2 mit Immutable Retention / Object Lock.

### 5.5 Unified SSO mit Passkeys & WebAuthn
- **Authentik als zentraler IdP:**
  - Vollständige Passwordless-Experience mittels FIDO2 / Passkeys (TouchID / YubiKey / Windows Hello).
  - Native OIDC-Anbindung für: Jellyfin, Grafana, Paperless-ngx, Mealie.
  - Caddy Forward-Auth Proxy für Anwendungen ohne natives OIDC (Sonarr, Radarr, Prowlarr, Sabnzbd, Bazarr).

### 5.6 Self-Hosted Notification Pipeline mit `ntfy`
- Betrieb eines eigenen **`ntfy.sh`** Servers auf `cld-edge-01` (`push.vyrx.de`).
- **Zentraler Push-Hub für:**
  - **Home Assistant:** Statusmeldungen, Alarme, Sensorik.
  - **Alertmanager / Grafana:** Storage, Host-Liveness, Metrik-Anomalien.
  - **CrowdSec:** Erkannte Brute-Force-Angriffe & IP-Bans.
  - **Arr-Stack:** Grab- und Download-Events.
  - **CI/CD:** Pipeline-Fehler und Build-Status.

### 5.7 AI Agent & Automation Mesh (OpenClaw & Hermes)
- **Zentrales Gateway auf `cld-ops-01`:** Betrieb des OpenClaw Gateways an Port `18789`.
- **Natives Mesh Peering:** Workstations (`hom-wrk-01`, `mob-nb-01`) und Server verbinden ihre Node-Instanzen direkt über das WireGuard-Mesh (`10.10.100.2:18789`) mit dem Gateway.
- **Eliminierung von Altlasten:** Vollständige Beseitigung aller fragilen SSH-Loopback-Tunnel zugunsten des nativen VPN-Overlays.

---

## 6. WLAN SSIDs

- **`VYRX`**: Hauptnetzwerk (VLAN 20 / WPA3-Personal)
- **`VYRX-IOT`**: Smart Home & Hardware (VLAN 30 / 2.4 GHz only / WPA2)
- **`VYRX-GUEST`**: Gäste (VLAN 99 / Isoliert)

---

## 7. Migrations-Phasenplan (Zero-Downtime & Zero-Rework)

1. **Phase 1: Domain Setup & Secrets-Restrukturierung**
   - Registrierung von `vyrx.de` und Cloudflare DNS-Zone einrichten.
   - Refactoring der `secrets/secrets.yaml` in hierarchische Namespaces (Beseitigung aller Host-Präfixe wie `_mackaye`).
2. **Phase 2: Codebase-Vorbereitung (Service Contracts & Dual-Stack VPN)**
   - Einführung von `my.contracts` und `my.topology` mit Zonen-Support.
   - Paralleler Rollout von Kernel-WireGuard (`wg0`) neben dem bestehenden Tailscale (`tailscale0`), um Lockouts auszuschließen.
   - Caddy auf Ingress-Host so konfigurieren, dass `.vyrx.de` parallel zu bestehenden Legacy-Domains bedient wird.
3. **Phase 3: Router, Subnetz- & Storage-Migration (Heimnetz)**
   - Umstellung des Heimnetz-Routers auf `10.10.0.0/16` und Umschalten von FRITZ!Box und TP-Link AP in den reinen Bridge-Modus (DHCP aus).
   - Etablierung des zentralen Gateways auf `hom-srv-01` (`features/system/networking/gateway` für DHCP, Blocky DNS, Chrony NTP und nftables-Routing).
   - Migration von `hom-srv-01` auf Disko-Btrfs (Vorbereitung für Impermanence und Tier-1 Snapshots).
   - Lokales DNS (Blocky) und lokaler Ingress-Caddy auf `hom-srv-01` für Split-Horizon DNS-01 ACME etablieren.
4. **Phase 4: Host-Renaming & Re-Keying (Sauberer Schnitt)**
   - Git-Branch anlegen und Host-Ordner nach Enterprise-Taxonomie umbenennen (`hosts/<new-name>/`).
   - `.sops.yaml` Age-Key-Namen anpassen und `secrets.yaml` mit neuen Host-Keys re-encrypten.
   - Gezieltes Deployment via `nod switch` über die verifizierten Verbindungs-IPs.
5. **Phase 5: WireGuard Cutover, OpenClaw Mesh & Observability**
   - Umschalten aller Dienst-Upstreams auf das WireGuard-Mesh (`10.10.100.x`).
   - OpenClaw Nodes direkt nativ über das Mesh mit `cld-ops-01` verbinden (Loopback-Tunnel entfernen).
   - Rollout von Vector/Loki für zentrales Logging und CrowdSec-Mesh.
   - Etablierung der 3-2-1 Restic-Pipeline mit Remote-Tier auf `cld-ops-01`.
6. **Phase 6: Decommissioning**
   - Tailscale vollständig deaktivieren und entfernen.
   - Entfernen aller temporären Legacy-Aliase (`.ancoris.ovh`) und Alt-Routen.

---

## 8. Codebase & NixOS-Architektur (nixfiles 2.0)

Dieses Kapitel definiert die software-architektonischen Prinzipien zur Realisierung einer akademisch sauberen, modularen und wartungsarmen NixOS-Infrastruktur.

### 8.1 Service Contract Pattern & Multi-Consumer Projections (SOLID: SRP, ISP, DIP, OCP)

Feature-Module sind strikt **agnostisch** und passiv. Ein Modul (z. B. Jellyfin) kennt weder seinen Zielhost, noch Routing-Details, noch die Caddy-Konfiguration.

- **Kanonischer Service-Contract (`my.contracts.provides`):**
  Dienste deklarieren rein ihre Schnittstellen und Anforderungen:
  ```nix
  # features/services/jellyfin/default.nix
  my.contracts.provides = {
    endpoints.web = {
      port = 8096;
      protocol = "tcp";
      scope = "public";      # "public" | "internal" | "mesh" | "isolated"
      auth = "none";         # "none" | "authentik" | "proxy-pass"
      subdomain = "jellyfin";
    };
    storage = {
      stateDirs = [ "/var/lib/jellyfin" ];
      cacheDirs = [ "/var/cache/jellyfin" ];
    };
  };
  ```
- **Deklarative Cluster-Platzierung (Inversion of Control):**
  Welcher Dienst auf welchem Rechner ausgeführt wird, bestimmt ausschließlich die Host-Komposition (z. B. `hosts/hom-srv-01/configuration.nix: my.features.services.jellyfin.enable = true;`).
- **Multi-Consumer Projection Pattern (Open/Closed Principle):**
  Spezialisierte Engines projizieren die aggregierten Contracts deterministisch in ihre Zielsysteme, ohne dass Module modifiziert werden müssen:
  - **Firewall Engine (Host-Lokal):** Projiziert `config.my.contracts.provides.endpoints` des eigenen Rechners direkt in typsichere `networking.firewall.interfaces`-Regeln.
  - **Ingress Engine (`cld-edge-01`):** Projiziert clusterweit alle `scope = "public"` Endpoints in Caddy-VHosts und WireGuard-Upstreams:
    $$\text{VHosts} = \Pi_{\text{public}}(\text{ClusterContracts})$$
  - **DNS Engine (`hom-srv-01`):** Projiziert alle internen Endpoints und Split-Horizon-Rewrites in Blocky-Hosts:
    $$\text{DNSRecords} = \Pi_{\text{dns}}(\text{ClusterContracts})$$

### 8.2 Secrets 2.0 (Hierarchische Domain-Taxonomie & Host-Agnostik)
Beseitigung der flachen Namens-Suppe und aller host-spezifischen Key-Namen (`_mackaye`).

- **Architektur-Garantie:**
  - `defaultSopsFile` verbleibt zentral in `secrets/secrets.yaml`.
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
- **Vorteile:** Services können im Cluster migriert werden, ohne Secret-Namen anzupassen. Typisierter Zugriff via `sops.secrets."services/authentik/ldap_outpost_token" = {};`.

### 8.3 Data Lifecycle & Multi-Tier Backup 2.0
Systematischer Ausbau zu einer deklarativen 3-2-1 Pipeline mit State-Consistency Garantien.

- **Pre-Backup Lifecycle Hooks:** Services mit transaktionalen Datenbanken deklarieren konsistente Snapshot-Hooks:
  ```nix
  contracts.storage.preBackupHook = pkgs.writeShellScript "pg-dump" ''
    ${pkgs.postgresql}/bin/pg_dumpall -U postgres > /var/backup/dump.sql
  '';
  ```
- **3-Tier Backup-Orchestrierung:**
  - **Tier 1 (Lokal):** Btrfs-Snapshots vor jedem System-Update.
  - **Tier 2 (Private Mesh):** Nächtlicher Restic-Backup-Push aller Server via WireGuard auf `cld-ops-01`.
  - **Tier 3 (Offsite Cold):** Verschlüsselter Sync kritischer Nutzdaten (Paperless-Dokumente, Vaultwarden, DB-Dumps) in externen S3/B2-Bucket mit Immutable Object Lock.

### 8.4 Deklarative Topologie-Registry & Mathematisches Trust Lattice
Zentralisierung aller Netzwerk-Definitionen in `my.topology` zur vollständigen Eliminierung hartcodierter IP-Listen.

- **Formales Sicherheitsmodell (Trust Lattice):**
  Zonen $\mathcal{Z}$ mit Ordnungsrelation:
  $$\mathcal{Z} = \{ \text{Guest}, \text{IoT}, \text{Mesh}, \text{Corp}, \text{Infra} \}$$
  $$\text{Guest} < \text{IoT} < \text{Mesh} \le \text{Corp} < \text{Infra}$$
- **Deterministische Flow-Matrix:**
  $$f(A, B) = \begin{cases} 
  \text{ALLOW (Direct Line-Speed)}, & \text{wenn } A = B \text{ (gleiche Zone/LAN)} \\
  \text{RESTRICTED (Stateful Pinholes)}, & \text{wenn } A > B \text{ (höheres Vertrauen initiiert)} \\
  \text{ISOLATED / DROP}, & \text{wenn } A < B \text{ (z. B. IoT } \to \text{ Infra)} \\
  \text{TUNNEL (WireGuard Mesh)}, & \text{wenn } A \text{ oder } B \in \text{Mesh}
  \end{cases}$$
- **Topologie-Struktur:**
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
      cld-edge-01 = { zone = "mesh"; ipv4 = "173.249.22.211"; wireguardIpv4 = "10.10.100.1"; };
      # ...
    };
  };
  ```

### 8.5 State- & Persistence-Katalog (Storage Tiering & Impermanence)
Standardisierte Trennung von Zustandstypen in Service-Modulen zur sauberen Koppelung an Speicherpfade, Disko-Subvolumes und Backup-Strategien.

- **Mathematisches Axiom des zustandslosen Systems (Impermanence):**
  $$\text{Node} = \text{Store}_{\text{immutable}} \oplus \text{Root}_{\text{tmpfs}} \oplus \text{Persist}(\text{State} \cup \text{Data})$$
  - Root (`/`) wird flüchtig im RAM (`tmpfs`) gemountet oder bei jedem Boot auf einen leeren Snapshot zurückgesetzt.
  - Nur deklarierte Pfade überleben Reboots:
    - **State (`stateDirs`):** Maschinenlesbare Runtime-Zustände, DBs (`/persist/state/...`).
    - **Data (`dataDirs`):** Unersetzliche Nutzerinhalte (`/persist/data/...`). Pflicht für Tier-3 Backup.
    - **Cache (`cacheDirs`):** Reproduzierbare Zwischendateien (`/var/cache/...`), flüchtig.

### 8.6 Profile-basiertes Home-Manager Design (Algebraische Komposition)
Vollständige Beseitigung von Host-State Leaks (`osConfig.my.role != "server"`) in User-Paketlisten.

- **Algebraische Komposition im System-Builder:**
  User-Konfigurationen sind modular und rollen-agnostisch. Der System-Builder injiziert atomare Profile als Kompositionsfunktion:
  $$\text{HomeConfig}(\text{Role}) = \begin{cases}
  \text{core} \cup \text{graphical}, & \text{wenn Role} \in \{\text{desktop}, \text{notebook}\} \\
  \text{core} \cup \text{diagnostics}, & \text{wenn Role} = \text{server}
  \end{cases}$$
- **Strikte Trennung:** User-Module deklarieren Werkzeuge, keine Verzweigungslogiken.

### 8.7 Service-Discovery & Cluster-weite Verdrahtung
Entkopplung von abhängigen Diensten über logische Namen.

- **Intent-basiertes Discovery:** Dienste referenzieren Zielservices über logische Namen (`coreEndpoint = "services.authentik";`), statt hartcodierte IPs und Ports einzubinden.
- **Automatische Auflösung:** Das Modul ermittelt via `my.contracts` den zuständigen Host und Port. Die IP wird über `my.topology` aufgelöst (WireGuard-IP für Out-of-Host Verbindungen, `127.0.0.1` für Co-Location). Wandert ein Dienst, erfolgt das Re-Wiring clusterweit automatisch beim nächsten Build.

### 8.8 Compile-Time Verification & Secret Schema Validation
Fehlerfrüherkennung bereits bei `nix flake check` / Eval-Zeit statt erst beim Systemstart.

- **Port-Kollisions-Beweis:**
  $$\forall s_1, s_2 \in \text{Services}(\text{Host}): s_1 \ne s_2 \implies \text{Port}(s_1) \ne \text{Port}(s_2)$$
- **Dangling Endpoint Assertion:**
  Generiert der Ingress einen VHost für einen Ziel-Service, validiert eine Assertion, dass der Dienst auf dem Zielknoten auch tatsächlich instanziiert ist.
- **Compile-Time SOPS Key Validator (`checks.eval-secrets`):**
  Da SOPS-YAML-Keys im Klartext vorliegen, validiert ein Nix-Check ohne private Age-Keys, dass alle von aktiven Modulen deklarierten Secret-Pfade in `secrets/secrets.yaml` existieren:
  $$\forall p \in \text{RequiredSecretPaths}(\text{ActiveModules}): p \in \text{Keys}(\text{secrets.yaml})$$

### 8.9 Flake Inputs & Overlay-Hygiene
Minimierung von Closure-Größen, Build-Zeiten und technischen Schulden.

- **Strikte Input-Harmonisierung:** Alle Flake-Inputs müssen zwingend `inputs.nixpkgs.follows = "nixpkgs-unstable"` deklarieren, um doppelte `nixpkgs`-Instanzen und unnötige Paket-Doppelbauten zu eliminieren.
- **Overlay-Lifecycle Policy:** Klare Ausmusterungskriterien für Patches unter `packages/overlays/fix/*`. Sobald Fixes im Upstream-Nixpkgs verfügbar sind, werden Overlays entfernt und veraltete Pinned Packages (z. B. insecure pnpm) bereinigt.
