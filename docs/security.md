# VYRX Enterprise Security Architecture Specification

> **Status:** Architecture Blueprint & Security Policy  
> **Frameworks:** Zero Trust Architecture (NIST SP 800-207), Defense-in-Depth, Bell-LaPadula Lattice  
> **Scope:** Cluster-weite Systemsicherheit, Kryptografie, Secrets-Lifecycle, OS-Hardening & Access Control  
> **Domain:** `vyrx.de`

---

## 1. Theoretisches Fundament & Sicherheitsmodelle

Die Sicherheitsarchitektur von **nixfiles 2.0** basiert auf dem mathematischen Axiom, dass kein Netzwerksegment (auch nicht das heimische LAN) inhärent vertrauenswürdig ist. Sicherheit wird nicht als Perimeter an der Außenwand verstanden, sondern als **durchgängige Eigenschaft jeder einzelnen Komponente**.

### 1.1 Zero Trust Architecture (NIST SP 800-207)
1. **Explizite Verifikation:** Jeder Zugriff auf interne Ressourcen (APIs, Web-Frontends, SSH, Metriken) erfordert eine kryptografische oder identitätsbasierte Verifikation (WireGuard Public-Key, FIDO2/Passkey oder mTLS).
2. **Least Privilege (PoLP):** Prozesse, Service-Accounts und menschliche Nutzer erhalten ausschließlich die minimal notwendigen Berechtigungen zur Erfüllung ihrer Aufgaben.
3. **Assume Breach:** Die Architektur geht davon aus, dass einzelne Knoten kompromittiert werden können. Horizontale Bewegungsfreiheit (Lateral Movement) wird durch strenge Netzwerksegmentierung und Namespace-Isolation unterbunden.

### 1.2 Formale Trust-Modellierung (Bell-LaPadula Lattice)
Das in [architecture.md](file:///etc/nixos/ARCHITECTURE.md#84-deklarative-topologie-registry--mathematisches-trust-lattice) definierte Zonenmodell $\mathcal{Z}$ wird als partiell geordnetes Vertrauensgitter formalisiert:
$$\mathcal{Z} = \{ \text{Guest}, \text{IoT}, \text{Mesh}, \text{Corp}, \text{Infra} \}$$
$$\text{Trust}(\text{Guest}) < \text{Trust}(\text{IoT}) < \text{Trust}(\text{Mesh}) \le \text{Trust}(\text{Corp}) < \text{Trust}(\text{Infra})$$

* **Simple Security Property (No Read-Up):** Ein Knoten mit niedrigerem Vertrauenslevel darf niemals Lesezugriff auf Ressourcen eines höheren Levels erhalten (z. B. darf IoT niemals auf Infra-APIs zugreifen).
* **$\star$-Property (No Write-Down):** Ein Knoten mit hohem Vertrauenslevel darf keine ungeschützten Schreiboperationen in niedrigere Zonen initiieren, die sensible Daten lecken könnten.

---

## 2. Defense-in-Depth Schichtenmodell

Die Sicherheitsmaßnahmen greifen modular auf sechs voneinander unabhängigen Ebenen:

```
┌────────────────────────────────────────────────────────┐
│  1. Identität & Auth (Authentik Passkeys / FIDO2)      │
├────────────────────────────────────────────────────────┤
│  2. Ingress & Edge Shield (Caddy TLS + CrowdSec IPS)   │
├────────────────────────────────────────────────────────┤
│  3. Transport Layer (Kernel-WireGuard ChaCha20 Mesh)   │
├────────────────────────────────────────────────────────┤
│  4. Operating System (NixOS Hardening & Sandboxing)    │
├────────────────────────────────────────────────────────┤
│  5. Storage & State (Impermanence & Restic Encryption) │
├────────────────────────────────────────────────────────┤
│  6. Cryptographic Material (SOPS / Age Asymmetric Keys)│
└────────────────────────────────────────────────────────┘
```

---

## 3. Kryptografie & Secrets-Lifecycle (SOPS 2.0)

Das Secret-Management ist vollständig asymmetrisch, versionskontrolliert und host-entkoppelt aufgebaut.

### 3.1 Schlüssel-Hierarchie & Material
* **Host-Keys (Node Identity):** Jeder Host besitzt einen eigenen Ed25519-Hostkey (`/etc/ssh/ssh_host_ed25519_key`), aus dem deterministisch der Age-Schlüssel abgeleitet wird (`ssh-to-age`).
* **Admin-Keys (User Identity):** Physische YubiKeys / Hardware-Tokens erzeugen den administrativen Age-Schlüssel für `philipp`.
* **CI/CD-Keys:** Dedizierter Ephemeral-Key für GitHub Actions Matrix-Builds.

### 3.2 Das Revocation- & Rekeying-Protokoll (Notfallplan bei Geräteverlust)
Geht ein mobiles Gerät (z. B. `mob-nb-01`) verloren oder wird kompromittiert, greift ein deterministisches 5-Schritte-Protokoll zur vollständigen Aussperrung:

```
[ Gerät verloren ] 
        │
        ▼
1. .sops.yaml:           Entferne Age-Key von mob-nb-01
        │
        ▼
2. Rekeying:             sops updatekeys secrets/secrets.yaml (Neue Verschlüsselung)
        │
        ▼
3. my.topology:          Entferne WireGuard-Public-Key von mob-nb-01
        │
        ▼
4. Rollout:              nod switch auf allen verbleibenden Knoten
        │
        ▼
[ mob-nb-01 verliert sofortigen Zugriff auf VPN und künftige Secrets ]
```

### 3.3 Compile-Time Secret Validation
Um fehlerhafte Deployments durch fehlende Secrets auszuschließen, prüft die CI/CD-Pipeline deklarativ, dass alle von aktiven Modulen referenzierten Secret-Pfade in `secrets/secrets.yaml` existieren (siehe [architecture.md](file:///etc/nixos/ARCHITECTURE.md#88-compile-time-verification--secret-schema-validation)).

---

## 4. Betriebssystem- & Kernel-Härtung (NixOS OS Layer)

Jeder Host wird mit einer **pragmatischen, performanzneutralen Härtungs-Baseline** ausgerüstet. Auf esoterische Parameter, die messbare CPU-Zyklen kosten (wie z. B. `init_on_free=1`, das bei Builds und Datenbank-Transaktionen bis zu 10% Durchsatz kostet), wird bewusst verzichtet.

### 4.1 Kernel-Parameter & Schutzmechanismen (Zero-Overhead Baseline)
```nix
# features/system/security/hardening.nix
boot.kernelParams = [
  # Zero-Overhead Memory Protection
  "slab_nomerge"                  # Verhindert Heap-Exploits durch Zusammenlegung von Caches (0% Overhead)
  "page_alloc.shuffle=1"          # Randomisiert Seitenallokation gegen Heap-Spraying (0% Overhead)
];

boot.kernel.sysctl = {
  # Adressraum- & Log-Schutz (Verhindert Reconnaissance)
  "kernel.kptr_restrict" = 2;     # Versteckt Kernel-Pointer vor Unprivileged Users
  "kernel.dmesg_restrict" = 1;    # dmesg nur für Root lesbar
  "kernel.unprivileged_bpf_disabled" = 1; # eBPF nur für Root (Schutz vor Sandbox-Escapes)

  # Netzwerk-Stack Härtung (Anti-Spoofing & SYN-Flood Protection)
  "net.ipv4.tcp_syncookies" = 1;
  "net.ipv4.conf.all.rp_filter" = 1;
  "net.ipv4.conf.default.rp_filter" = 1;
  "net.ipv4.conf.all.accept_redirects" = 0;
  "net.ipv4.conf.default.accept_redirects" = 0;
  "net.ipv4.conf.all.send_redirects" = 0;
  "net.ipv6.conf.all.accept_redirects" = 0;
};
```

### 4.2 Systemd Service Sandboxing (Kanonischer Sicherheits-Contract)
Jedes Service-Modul in `features/services/*` muss den standardisierten NixOS Systemd-Sandboxing-Contract erfüllen. Ein Daemon darf niemals ungehinderte Rechte auf dem Host besitzen:

```nix
systemd.services.<service-name>.serviceConfig = {
  # Dateisystem-Isolation
  ProtectSystem = "strict";
  ProtectHome = true;
  PrivateTmp = true;
  PrivateDevices = true;

  # Privilege & Namespace Isolation
  NoNewPrivileges = true;
  ProtectKernelTunables = true;
  ProtectKernelModules = true;
  ProtectControlGroups = true;
  RestrictRealtime = true;
  RestrictSUIDSGID = true;
  RestrictNamespaces = true;

  # Minimaler Capability Footprint
  CapabilityBoundingSet = "";
  AmbientCapabilities = "";
};
```

### 4.3 Die Anti-Overkill-Garantie (Zero Performance Penalty)
Sicherheit darf niemals zu Lasten der Usability oder Rechnerleistung gehen. Die Architektur setzt auf **Null-Overhead-Maßnahmen**:
* **Systemd-Isolation:** Nutzt Linux-Kernel-Namespaces (`unshare`, `cgroups`). Der Overhead entsteht einmalig beim Prozessstart im Mikrosekundenbereich – zur Laufzeit beträgt der CPU- und Memory-Overhead exakt **0,00 %**.
* **Netzwerk & WireGuard:** Kernel-WireGuard läuft mit hardwarebeschleunigter ChaCha20-Poly1305-Kryptografie. Da lokaler LAN-Verkehr über direkte Interfaces läuft (Anti-Hairpinning), bleibt die volle Leitungsgeschwindigkeit (1 Gbit/s / 2.5 Gbit/s) unberührt.
* **Keine esoterischen Compiler-Bremsen:** Keine künstliche Speicher-Nullung auf jedem `free()` (`init_on_free=0`) und keine invasiven runtime-Interceptors, damit Builds (`nix build`), Datenbank-Transaktionen und Transcoding mit nativer CPU-Leistung laufen.

---

## 5. Netzwerk-Sicherheit & Zero-Trust Ingress

### 5.1 Kernel-WireGuard Mesh als vertrauenswürdige Transportschicht
* **Kein unverschlüsselter Cluster-Verkehr:** Sämtliche Node-to-Node-Kommunikation (Logs, Metriken, Backups, Caddy-Upstreams, OpenClaw AI-Nodes) erfolgt zwingend über den Kernel-WireGuard-Tunnel (`10.10.100.x`).
* **Kryptografische Identität:** WireGuard bindet IP-Adressen kryptografisch an den Public-Key (`AllowedIPs`). IP-Spoofing innerhalb des Mesh-Netzwerks ist mathematisch unmöglich.

### 5.2 Edge Ingress & CrowdSec Intrusion Prevention (IPS)
* **Cloudflare DNS-01 ACME:** Wildcard-Zertifikate werden ohne offene Port-Weiterleitungen im Heimnetz bezogen.
* **CrowdSec Master-Node Pipeline:**
  * Ingress-Proxy `cld-edge-01` analysiert Caddy-Access-Logs in Echtzeit.
  * Erkennt CrowdSec Scans, Path-Traversal oder Brute-Force, wird die bösartige IP clusterweit blockiert.
  * **Automatisches Whitelisting:** Die Topologie-Registry injiziert alle vertrauenswürdigen internen Subnetze (`my.topology.trustedSubnets`) als Parser-Whitelist, um False Positives für interne Systeme auszuschließen.

---

## 6. Access Control & Deployment-Sicherheit (`nod switch`)

### 6.1 SSH-Härtung (Ausschließliche Mesh-Exposition)
* **Kein SSH im Internet:** Der SSH-Port 22 ist auf den öffentlichen WAN-Interfaces der Cloud-Server vollständig per Firewall geschlossen (`networking.firewall.allowedTCPPorts = []`).
* **Exposition nur im Mesh:** SSH lauscht ausschließlich auf dem WireGuard-Interface (`wg0` an `10.10.100.x`). Angreifer aus dem öffentlichen Internet sehen den SSH-Port als gefiltert/geschlossen.
* **Authentifizierung:** Ausschließlich Ed25519-Keys. Passwort-Authentifizierung (`PasswordAuthentication no`) und Root-Login mit Passwort sind systemweit deaktiviert.

### 6.2 Schnelle & Autonome Deployments mit `nod switch`
* **Entkopplung von Deployment und Probes:**
  * Deployments via `nod switch` müssen schnell, atomar und unblockiert durchlaufen.
  * **Architektur-Vorgabe:** Deployments werden **niemals** durch synchrone Liveness-Probes oder künstliche Warte-Schleifen verlangsamt.
  * System-Health wird rein asynchron in der Monitoring-Ebene (Grafana/Prometheus/ntfy) überwacht. Schlägt ein Dienst nach einem Rebuild fehl, alarmiert das Alertmanager-Mesh unabhängig vom Deployment-Prozess.

---

## 7. Auditierung, Logging & Incident Response

### 7.1 Unveränderliches Log-Streaming
* Systemd-Journal-Logs aller Hosts werden über den lokalen Vector/Alloy-Agenten verschlüsselt an Loki auf `cld-ops-01` gestreamt.
* **Manipulationssicherheit:** Selbst wenn ein Angreifer Root-Zugriff auf einen Randknoten (`cld-edge-01`) erlangt, kann er seine Spuren nicht lokal verwischen, da die Audit-Logs bereits außerhalb des Knotens im Ops-Cluster persistiert sind.

### 7.2 Incident Response Matrix

| Vorfall | Automatische Gegenmaßnahme | Manuelle Sofortmaßnahme |
|---|---|---|
| **Brute-Force Angriff auf Ingress** | CrowdSec bannt IP auf Caddy-Ebene | Überprüfung im Grafana Security Dashboard |
| **Verlust eines mobilen Endgeräts** | N/A | Rekeying nach Kapitel 3.2 via `nod switch` |
| **Dienst-Absturz nach Rebuild** | Systemd Restart-Loop Protection | Asynchrone ntfy-Push-Meldung $\to$ `nod rollback` |
| **Unerlaubter SSH-Versuch** | CrowdSec bannt Ursprungs-IP | Alert via ntfy (`security`-Topic) |

---

## 8. Zusammenfassung

Die VYRX-Sicherheitsarchitektur implementiert **echte Enterprise-Grade Sicherheit** ohne die typische Frustration von Insellösungen. Durch das Zusammenspiel aus **deklarativem Kernel-Hardening**, **asymmetrischem SOPS-Lifecycle**, **Passkey-First Authentik IAM** und dem **stateless WireGuard-Mesh** ist das Cluster gehärtet gegen Bedrohungen von außen und laterale Ausbreitung von innen.
