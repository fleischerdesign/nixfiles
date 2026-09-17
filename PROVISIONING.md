# VYRX Declarative Service Provisioning & Configuration-as-Code Specification

> **Status:** Architecture Blueprint & Implementation Guide  
> **Scope:** Zero-ClickOps Service Provisioning (Dashboard, Grafana, Klipper, Home Assistant, CrowdSec, ntfy, Arr-Stack)  
> **Design Goals:** Vollständige Reproduzierbarkeit, SOLID-Entkopplung, DRY-Synthese, Inversion of Control, State/Code Separation.

---

## 1. Leitphilosophie & Der „Zero-ClickOps“-Standard

In vielen modernen Self-Hosted-Setups wird zwar das Basissystem via NixOS deklarativ installiert, die eigentliche Applikationskonfiguration (Dashboards, Drucker-Makros, Kamera-Streams, Whitelists, Berechtigungen) verbleibt jedoch in webbasierten Einstellungsmasken („ClickOps“). Dies führt zu **Wartungsschulden**, **Konfigurationsdrift** und **langen Wiederanlaufzeiten im Desasterfall**.

### Das Zero-ClickOps-Axiom für nixfiles 2.0:
> **Web-UIs dienen ausschließlich als Kontroll- und Visualisierungsschnittstelle, niemals als primärer Konfigurationsspeicher.**  
> Jede Applikation wird in ihrer Architektur strikt in **unveränderliche Konfiguration (Git)** und **flüchtigen Zustand (State/DB)** getrennt:
> $$\text{ServiceInstance} = \text{ImmutableConfig}_{\text{Git/Nix}} \oplus \text{RuntimeState}_{\text{DB/Files}}$$

---

## 2. Das kompilierte Cluster-Dashboard (Homarr / Glance aus `my.contracts`)

Anstatt Kacheln, Links, Icons und Gruppen im Web-UI händisch zu pflegen, wird das zentrale Dashboard **als funktionale Projektion direkt aus dem Service-Katalog kompiliert**.

### 2.1 Das Multi-Consumer Projektions-Prinzip:
Da jeder Dienst über seinen Service-Contract (`my.contracts.provides.endpoints`) seine Eigenschaften deklariert, leitet der System-Builder das Dashboard deterministisch ab:

$$\text{DashboardConfig} = \Pi_{\text{dashboard}}(\text{ClusterEndpoints})$$

```nix
# Reines, agnostisches Projektions-Muster
dashboardTiles = lib.mapAttrsToList (name: ep: {
  title = ep.displayName or name;
  url = ep.publicUrl or ep.localUrl;
  category = ep.category or "Services";
  icon = ep.icon or "default";
  pingUrl = ep.healthProbeUrl;
}) (lib.filterAttrs (_: ep: ep.dashboard.show) config.my.contracts.provides.endpoints);
```

### 2.2 Architektur-Vorteile (SOLID & DRY):
* **Single Source of Truth (SSOT):** Ein neuer Dienst deklariert `dashboard.show = true; dashboard.category = "Media";`.
* **Zero-Touch:** Beim nächsten `nod switch` erscheint die Kachel automatisch in der richtigen Kategorie mit korrekter URL und Liveness-Ping.
* **Keine toten Links:** Wandert ein Dienst oder ändert sich eine Domain, aktualisiert sich das Dashboard clusterweit atomar.

---

## 3. Grafana: Dashboards as Code & Alert-Governance

Alerts und Datasources sind bereits in [features/services/monitoring/grafana/default.nix](file:///etc/nixos/features/services/monitoring/grafana/default.nix) in NixOS deklariert. Dashboards werden nach demselben Prinzip vollständig aus dem UI verbannt.

### 3.1 Das Provisioning-Pattern:
Grafana provisioniert Dashboards idempotent über Dateisystem-Provider:

```
features/services/monitoring/grafana/
├── default.nix
└── dashboards/
    ├── node-exporter-full.json     # Hardware-Telemetrie aller 5 Hosts
    ├── caddy-web-traffic.json      # Ingress Access, Request-Rates, Status-Codes
    ├── crowdsec-threats.json       # Gebannte Angreifer, aktive Scenarios
    ├── wireguard-mesh.json         # Latenzmatrix, Rx/Tx Throughput
    └── zfs-btrfs-storage.json      # Pool-Health, Snapshot-Counts
```

### 3.2 Deklarative Verdrahtung in NixOS:
```nix
services.grafana.provision.dashboards.settings.providers = [
  {
    name = "vyrx-system-dashboards";
    type = "file";
    options = {
      path = ./dashboards;
      foldersFromFilesStructure = true;
    };
    disableDeletion = false;
    updateIntervalSeconds = 60;
  }
];
```

* **Vorteil:** Dashboards sind versioniert, änderbar per Git-Pull-Request und immun gegen versehentliches Überschreiben im UI.

---

## 4. Klipper & Moonraker (3D-Drucker: State/Code Separation)

Aktuell liegt die Druckerkonfiguration mutabel in `/var/lib/klipper`. Für einen stabilen Betrieb wird die Konfiguration formal in **statischen Maschinencode** und **dynamischen Kalibrierungszustand** entkoppelt.

### 4.1 Die Formale Klipper-Gleichung:
$$\text{KlipperConfig} = \text{Store}_{\text{cfg}} (\text{Steppers} \cup \text{Kinematics} \cup \text{Macros}) \oplus \text{Include}(\text{State}_{\text{bed\_mesh, pid}})$$

### 4.2 Verzeichnis- & Modul-Layout:
```
features/services/klipper/
├── default.nix
└── printer-config/
    ├── steppers.cfg            # Motoren, TMC2209 Treiber, Endstopps
    ├── kinematics.cfg          # CoreXZ/Cartesian Geometrie, Beschleunigung
    ├── heaters.cfg             # Hotend, Heizbett, Thermistoren
    └── macros/
        ├── start-print.cfg     # Adaptives Vorheizen, Nozzle-Purge, Mesh-Load
        ├── end-print.cfg       # Retract, Parken, Heizer abschalten
        └── filament.cfg        # Be- und Entladeprozeduren
```

### 4.3 Deklarative Einbindung in NixOS:
```nix
services.klipper = {
  enable = true;
  mutableConfig = true; # Erlaubt Klipper, SAVE_CONFIG auszuführen
  configFile = pkgs.writeText "printer-master.cfg" ''
    # Immutable Core-Definitionen aus dem Nix-Store
    [include ${./printer-config/steppers.cfg}]
    [include ${./printer-config/kinematics.cfg}]
    [include ${./printer-config/heaters.cfg}]
    [include ${./printer-config/macros/start-print.cfg}]
    [include ${./printer-config/macros/end-print.cfg}]

    # Flüchtiger Zustand (Bed-Mesh, Z-Offset, PID-Werte)
    [include /var/lib/klipper/runtime_variables.cfg]
  '';
};
```

* **Vorteil:** Die exakte Funktionsweise des Druckers ist im Git gesichert. Nach einem System-Rebuild druckt die Maschine sofort mit den optimierten Parametern weiter.

---

## 5. Home Assistant: Lovelace YAML & Automation Pipelines

Statt über den graphischen Editor im Browser unübersichtliche JSON-Blobs in `.storage/` anzuhäufen, werden zentrale Dashboards und sicherheitskritische Automatisierungen im Code verankert.

### 5.1 Lovelace Dashboards im YAML-Modus:
```nix
services.home-assistant.config = {
  # Lovelace deklarativ erzwingen
  lovelace = {
    mode = "yaml";
    resources = [
      # Benutzerdefinierte Kacheln und Klipper-Karten
    ];
  };
};

services.home-assistant.lovelaceConfig = {
  title = "VYRX Smart Infrastructure";
  views = [
    {
      title = "Overview";
      path = "overview";
      cards = [
        {
          type = "picture-entity";
          entity = "camera.mainsail_cam";
          name = "3D Printer Bed";
        }
        {
          type = "entities";
          title = "System State";
          entities = [
            "sensor.strummer_storage_free"
            "binary_sensor.cld_edge_01_status"
          ];
        }
      ];
    }
  ];
};
```

### 5.2 Kritische Automatisierungen in Nix:
Sicherheits- und Workflow-Automatisierungen werden direkt als Attrset deklariert:
```nix
services.home-assistant.config.automation = [
  {
    alias = "3D Print Completed Notification";
    trigger = [
      {
        platform = "state";
        entity_id = "sensor.klipper_print_status";
        to = "complete";
      }
    ];
    action = [
      {
        service = "notify.vyrx_ntfy";
        data = {
          title = "3D-Druck abgeschlossen";
          message = "Druckvorgang erfolgreich beendet.";
          data = { priority = "high"; };
        };
      }
    ];
  }
];
```

---

## 6. CrowdSec: Deterministische Whitelist- & Bouncer-Synthese

Ein Hauptproblem bei IPS-Systemen (Intrusion Prevention) sind False Positives, die interne Knoten bei Monitoring-Probes oder Backups aussperren.

### 6.1 Automatische Whitelist-Ableitung:
Anstatt manuelle IP-Listen zu pflegen, synthetisiert NixOS die Whitelist direkt aus der Topologie-Registry:

$$\text{CrowdsecWhitelist} = \bigcup_{s \in \text{subnets}} \{ s.cidr \mid s.trustLevel \ne \text{"zero"} \}$$

### 6.2 Deklarative Parser-Injektion:
```nix
environment.etc."crowdsec/parsers/s02-enrich/00-topology-whitelist.yaml".text = builtins.toJSON {
  name = "vyrx/topology-whitelist";
  description = "Auto-generated whitelist from my.topology";
  whitelist = {
    reason = "Trusted infrastructure zones";
    cidr = config.my.topology.trustedSubnets;
  };
};
```

* **Ergebnis (100% DRY):** Ändert sich ein Subnetz in `my.topology`, passt sich die Firewall und die CrowdSec-Whitelist clusterweit vollautomatisch an.

---

## 7. ntfy.sh: Deklarative Topic-Governance & Access Control

Um unbefugtes Triggern von Benachrichtigungen zu verhindern, wird ntfy mit einer strikten Access Control List (ACL) versehen.

### 7.1 Topic- & Rollenmatrix:

| Topic | Publisher | Subscriber | Kritikalität |
|---|---|---|---|
| `alerts` | Grafana / Alertmanager | Admin (`philipp`) | Hoch (Storage, Host down) |
| `security`| CrowdSec Ingress | Admin (`philipp`) | Kritisch (Bans, Angriffe) |
| `home` | Home Assistant | Familie (`family`) | Normal (Waschmaschine, Türklingel) |
| `media` | Sonarr / Radarr | Admin (`philipp`) | Niedrig (Grabbed / Imported) |
| `ci` | GitHub Actions / Hermes | Dev (`philipp`) | Normal (Builds) |

### 7.2 Deklarative Konfiguration:
```nix
services.ntfy-sh.settings = {
  base-url = "https://push.vyrx.de";
  auth-file = config.sops.templates."ntfy-auth.env".path;
  auth-default-access = "deny-all"; # Zero-Trust Default
};

# SOPS Template generiert deklarative Benutzer und Rechte:
sops.templates."ntfy-auth.env".content = ''
  # Benutzerkonten mit festen Tokens aus SOPS
  user add --role=admin philipp ${config.sops.placeholder."users/philipp/ntfy_token"}
  user add grafana ${config.sops.placeholder."observability/grafana/ntfy_token"}
  user add crowdsec ${config.sops.placeholder."services/crowdsec/ntfy_token"}

  # Access Control Policies (read-write, write-only, read-only)
  access grafana alerts write-only
  access crowdsec security write-only
  access philipp * read-write
'';
```

---

## 8. Arr-Stack & Usenet: Zero-Touch API Bootstrap & Sabnzbd GitOps

Recyclarr synchronisiert bereits Quality Profiles und Custom Formats. Die verbleibenden manuellen Verknüpfungen (Root Folders, Download Clients, Naming Conventions) werden per Config-as-Code gelöst.

### 8.1 Sabnzbd `.ini` Deklaration:
Sabnzbd liest Konfigurationen aus `sabnzbd.ini`. Server-Verbindungen, Download-Limits und Kategorien werden über NixOS vorgegeben:
```nix
sops.templates."sabnzbd.ini".content = ''
  [misc]
  download_dir = /data/storage/downloads/incomplete
  complete_dir = /data/storage/downloads/complete

  [categories]
  [[tv]]
  name = tv
  dir = /data/storage/downloads/tv
  [[movies]]
  name = movies
  dir = /data/storage/downloads/movies
'';
```

### 8.2 One-Shot API Bootstrap Service:
Für Sonarr und Radarr sorgt ein idempotenter systemd-Oneshot-Dienst beim ersten Start dafür, dass Root-Pfade und Sabnzbd-Verbindungen via REST-API angelegt werden:
```nix
systemd.services.sonarr-bootstrap = {
  description = "Sonarr Root Folder & Client Initializer";
  after = [ "sonarr.service" ];
  wantedBy = [ "multi-user.target" ];
  script = ''
    API_KEY=$(cat ${config.sops.secrets.sonarr_api_key.path})
    # Prüfen ob Root-Folder existiert, falls nicht: anlegen
    ${pkgs.curl}/bin/curl -s -f -H "X-Api-Key: $API_KEY" http://127.0.0.1:8989/api/v3/rootfolder \
      -X POST -d '{"path": "/data/storage/tv"}' -H "Content-Type: application/json" || true
  '';
};
```

---

## 9. Architektur-Matrix: Von ClickOps zu nixfiles 2.0

| Domäne | Früher (ClickOps im Web-UI) | nixfiles 2.0 (Zero-ClickOps GitOps) |
|---|---|---|
| **Dashboard** | Kacheln manuell im Browser angeordnet | **Vollautomatisch aus `my.contracts`** kompiliert |
| **Grafana** | JSON-Dateien manuell ins UI importiert | **Declarative Dashboards** unter `dashboards/*.json` |
| **Klipper / 3D** | `printer.cfg` mutabel in `/var/lib/klipper` | **Hardware & Makros in Git**, nur Kalibrierungsdaten mutabel |
| **Home Assistant**| Dashboard im UI zusammengeklickt | **Lovelace YAML Config** im Repo |
| **CrowdSec** | Manuelle IP-Whitelists gegen False Positives | **Synthetisiert direkt aus `my.topology`** |
| **ntfy.sh** | Offene Topics ohne Autorisierung | **Deklarative Access Control List (ACL)** via SOPS |
| **Arr / Sabnzbd**| Download-Clients & Pfade im UI verknüpft | **Idempotenter API-Bootstrap** & `.ini`-Template |

---

## 10. Fazit

Durch die konsequente Umsetzung dieser Spezifikation wird der gesamte Service-Stack **deterministisch, disaster-recovery-fähig und wartungsfrei**. Das Web-UI dient nur noch dem Monitoring und der Nutzung – die Kontrolle liegt zu 100 % im Git-Repository.
