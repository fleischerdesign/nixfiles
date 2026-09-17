# VYRX Agentless Hardware & Embedded Device Specification

> **Status:** Architecture Blueprint & Implementation Guide  
> **Scope:** OpenWrt Wi-Fi Access Points, ESPHome Microcontrollers & Embedded Hardware GitOps  
> **Design Goals:** Unified Developer Experience (`nod switch`), Agentless Declarative Compilation, SOPS Secret-Inversion, 100% DRY.

---

## 1. Leitphilosophie & Das „Dumb Device, Smart Control-Plane“-Axiom

In modernen Infrastrukturen stellen eingebettete Geräte (Wi-Fi Access Points, Smart-Home-Sensoren, Mikrocontroller) oft eine Bruchstelle dar: Sie besitzen zu wenig Speicherplatz (Flash/RAM) für eine vollwertige NixOS-Installation, weshalb Administratoren sie manuell über proprietäre Web-UIs oder Insellösungen konfigurieren („ClickOps-Falle“).

### Das Agentless GitOps-Axiom für nixfiles 2.0:
> **Der Nix-Store und der Compiler verbleiben auf der Build-Maschine.**  
> Embedded Targets werden als **agentless Compile-Targets** im Flake modelliert. Nix kompiliert die firmware-spezifischen Konfigurationen oder Binaries auf der x86-Workstation und deployt sie über standardisierte Transportschichten (SSH/SCP, OTA) auf das Zielgerät:
> $$\text{DeployTarget}(T) = \text{Compile}_{\text{Nix}}(\text{Spec}_T, \text{Secrets}_{\text{SOPS}}) \xrightarrow[\text{SSH / OTA}]{\text{Atomic Push}} \text{TargetDevice}_T$$

---

## 2. SOLID-Modellierung der universellen Node-Architektur

Unabhängig davon, ob ein Zielgerät ein Multi-Core-Server mit NixOS, ein OpenWrt-Router oder ein ESP32-Microcontroller ist: Die Schnittstelle für den Administrator bleibt **vollständig polymorph und identisch** (Liskov Substitution Principle).

```
                            ┌────────────────────────────────────────────────────────┐
                            │          my.topology & secrets.yaml (SSOT)             │
                            └───────────────────────────┬────────────────────────────┘
                                                        │
                                                        ▼
                            ┌────────────────────────────────────────────────────────┐
                            │                  flake.nix / nod CLI                   │
                            │                  `nod switch <target>`                 │
                            └───────┬───────────┬───────────────┬────────────┬───────┘
                                    │           │               │            │
            ┌───────────────────────┘           │               │            └───────────────────────┐
            ▼                                   ▼               ▼                                    ▼
┌───────────────────────┐   ┌───────────────────────┐   ┌───────────────────────┐    ┌───────────────────────┐
│  Target: NixOS Host   │   │  Target: OpenWrt AP   │   │ Target: FRITZ!Box RT  │    │  Target: ESPHome MCU  │
│  (hom-srv-01, etc.)   │   │  (hom-ap-01)          │   │ (hom-rt-01)           │    │  (living-room-sensor) │
├───────────────────────┤   ├───────────────────────┤   ├───────────────────────┤    ├───────────────────────┤
│ Build: nixosSystem    │   │ Build: UCI Derivation │   │ Build: TR-064 Spec    │    │ Build: esphome compile│
│ Push:  SSH + switch   │   │ Push:  SCP + reload   │   │ Push:  SOAP/HTTPS API │    │ Push:  OTA Flash      │
└───────────────────────┘   └───────────────────────┘   └───────────────────────┘    └───────────────────────┘
```

1. **Single Responsibility Principle (SRP):**
   * Das Zielgerät führt ausschließlich seinen Einsatzzweck aus (Funkwellen übertragen, Sensordaten erfassen).
   * Die Konfigurations-Synthese und Secret-Injektion ist vollständig an Nix ausgelagert.
2. **Open/Closed Principle (OCP):**
   * Das System ist offen für neue Hardware-Typen (z. B. Zigbee-Bridges, Managed Switches): Es wird lediglich ein neuer Generator-Adapter definiert; der Deployment-Workflow `nod switch` bleibt unverändert.
3. **Dependency Inversion Principle (DIP):**
   * Embedded-Geräte hängen nicht von hardcodierten lokalen Einstellungen ab, sondern von der zentralen Topologie (`my.topology`) und den verschlüsselten Secrets (`secrets.yaml`).
4. **Don't Repeat Yourself (DRY):**
   * WLAN-SSIDs (`VYRX`, `VYRX-IOT`) und WPA3-Passwörter existieren **ein einziges Mal** in SOPS und werden deterministisch in OpenWrt-UCI und ESPHome-YAML gerendert.

---

## 3. TP-Link RE330 Wi-Fi Access Point (`hom-ap-01`)

Der TP-Link RE330 Wi-Fi Repeater/Access Point wird im Access-Point-Modus als reine Layer-2-Funkbrücke (`hom-ap-01`) in die Infrastruktur integriert (SSIDs: `VYRX`, `VYRX-IOT`). Sämtliche Netzwerkdienste (DHCP, DNS, Routing) werden zentral von `hom-srv-01` bereitgestellt.

### 3.1 Host-Definition im Flake (`hosts/hom-ap-01/default.nix`)
```nix
# hosts/hom-ap-01/default.nix
{ pkgs, config, ... }:
let
  wifiSecret = config.sops.placeholder."services/wifi/wpa3_key";
  iotWifiSecret = config.sops.placeholder."services/wifi/iot_key";
in
{
  targetType = "openwrt";
  hostname = "hom-ap-01";
  ipv4 = "10.10.10.20";
  zone = "infra";

  # Deklarative Generierung der OpenWrt UCI-Konfigurationsdateien
  configFiles = {
    # 1. Netzwerk & Bridge (Reiner Dumb-AP Modus)
    "/etc/config/network" = pkgs.writeText "openwrt-network" ''
      config interface 'loopback'
          option device 'lo'
          option proto 'static'
          option ipaddr '127.0.0.1'
          option netmask '255.0.0.0'

      config device 'br_lan'
          option name 'br-lan'
          option type 'bridge'
          list ports 'lan1'
          list ports 'lan2'

      config interface 'lan'
          option device 'br-lan'
          option proto 'static'
          option ipaddr '10.10.10.20'
          option netmask '255.255.255.0'
          option gateway '10.10.10.10'
          option dns '10.10.10.10'
    '';

    # 2. Drahtlosnetzwerk (SSIDs, WPA3 & Multi-BSSID)
    "/etc/config/wireless" = pkgs.writeText "openwrt-wireless" ''
      config wifi-device 'radio0'
          option type 'mac80211'
          option path 'platform/soc/...'
          option channel '36'
          option band '5g'
          option htmode 'HE80'
          option country 'DE'

      # Primäres Netzwerk (CORP / Workstations)
      config wifi-iface 'wifinet0'
          option device 'radio0'
          option mode 'ap'
          option network 'lan'
          option ssid 'VYRX'
          option encryption 'sae'
          option key '${wifiSecret}'

      # Isoliertes IoT Netzwerk
      config wifi-iface 'wifinet1'
          option device 'radio0'
          option mode 'ap'
          option network 'lan'
          option ssid 'VYRX-IOT'
          option encryption 'psk2'
          option key '${iotWifiSecret}'
    '';
  };

  # Atomarer Reload-Befehl nach Dateiübertragung
  reloadCommand = "/etc/init.d/network reload && wifi reload";
}
```

### 3.2 Der Deployment-Ablauf via `nod switch hom-ap-01`:
1. `nod` liest die Host-Definition und rendert die Konfigurationsdateien via Nix.
2. `nod` baut eine SSH-Verbindung zu `root@10.10.10.20` über das interne Management-Netz auf.
3. Die generierten UCI-Dateien werden atomar nach `/etc/config/` kopiert.
4. `nod` führt `reloadCommand` aus $\to$ Die neuen WLAN-Parameter sind in unter 2 Sekunden aktiv.
5. **Ergebnis:** Kein Web-Interface, kein manuelles Klicken, 100% reproduzierbar.

---

## 4. FRITZ!Box Router GitOps (`hom-rt-01`) via TR-064 API

Die FRITZ!Box fungiert als reiner WAN-Uplink und DSL/Glasfaser-Modem. Da auf Closed-Source-FRITZ!OS kein SSH zur Verfügung steht, nutzt der Nix-Adapter das standardisierte **AVM TR-064 Protokoll (SOAP/HTTPS via Port 49443)**.

### 4.1 Host-Definition (`hosts/hom-rt-01/default.nix`)
```nix
# hosts/hom-rt-01/default.nix
{ config, ... }:
{
  targetType = "fritzbox";
  hostname = "hom-rt-01";
  ipv4 = "10.10.10.1";
  zone = "infra";

  # Deklarativer Soll-Zustand (Declarative Desired State)
  settings = {
    dns = {
      primary = "10.10.10.10";  # hom-srv-01 (Blocky DNS)
      fallback = "1.1.1.1";
    };
    dhcp = {
      enable = false;           # Übernimmt hom-srv-01 zentral
    };
    portForwardings = [ ];      # Zero Open Ports auf dem Router
    wifi = {
      enable = true;
      guestEnable = false;
    };
  };
}
```

### 4.2 Der Deployment-Ablauf via `nod switch hom-rt-01`:
1. `nod` liest den deklarierten Soll-Zustand aus Nix.
2. Das FRITZ!Box-Admin-Passwort wird sicher aus SOPS (`services/fritzbox/password`) bezogen.
3. Ein in Nix verpacktes Python-Skript (`fritzconnection`) verbindet sich verschlüsselt mit der TR-064-Schnittstelle auf `10.10.10.1:49443`.
4. Der Zustand wird **idempotent abgeglichen** (DNS-Server setzen, DHCP deaktivieren, Ports schließen).
5. **Ergebnis:** Kein Login ins Web-Interface, kein manuelles Klicken, Router-Konfiguration 100% synchron mit Git.

---

## 5. ESPHome Microcontroller GitOps

Microcontroller (ESP32, ESP8266) steuern Sensorik, LED-Stripes und Schalter im Haus. Sie werden nach demselben deklarativen Schema als first-class Compile-Targets geführt.

### 5.1 Modulares Komponenten-Layout:
```
features/services/esphome/
├── default.nix                   # ESPHome Dashboard (optional)
├── common/
│   ├── base.yaml                 # Standard: Logging, OTA, Wi-Fi, Fallback AP
│   └── time.yaml                 # NTP Sync gegen hom-srv-01 (10.10.10.10)
└── devices/
    ├── living-room-sensor.yaml   # Raumklima & Anwesenheit
    ├── desk-ambient-light.yaml   # WLED / Adressierbare LEDs
    └── klipper-chamber-temp.yaml # Zusätzliche Bauraum-Temperatur
```

### 5.2 Deklarative Base-Konfiguration (`common/base.yaml`):
```yaml
# features/services/esphome/common/base.yaml
esphome:
  name: !extend
  min_version: "2024.6.0"

wifi:
  ssid: !secret wifi_iot_ssid
  password: !secret wifi_iot_password
  manual_ip:
    static_ip: !extend
    gateway: 10.10.10.10
    subnet: 255.255.255.0
    dns1: 10.10.10.10

ota:
  platform: esphome
  password: !secret ota_password

logger:
  level: INFO

time:
  - platform: sntp
    servers:
      - 10.10.10.10
```

### 5.3 Geräte-Spezifikation (`devices/living-room-sensor.yaml`):
```yaml
# features/services/esphome/devices/living-room-sensor.yaml
packages:
  base: !include ../common/base.yaml

esphome:
  name: living-room-sensor

esp32:
  board: esp32dev
  framework:
    type: esp-idf

wifi:
  manual_ip:
    static_ip: 10.10.30.25 # Direkt im IoT-Subnetz verankert

sensor:
  - platform: bme280_i2c
    temperature:
      name: "Wohnzimmer Temperatur"
    humidity:
      name: "Wohnzimmer Luftfeuchtigkeit"
    pressure:
      name: "Wohnzimmer Luftdruck"
    address: 0x76
```

### 5.4 Deployment via `nod switch living-room-sensor`:
```bash
# Kompiliert das Binary hermetisch in Nix und schiebt es per OTA auf den ESP32:
nod switch living-room-sensor
```

---

## 6. Cloudflare Edge & DNS GitOps Target (`cld-dns` / `cloudflare`)

Statt DNS-Records, Proxied-Status und Edge-TLS manuell im Cloudflare-Webdashboard zu pflegen („ClickOps-Falle“), existiert ein vollständig deklaratives Target für Cloudflare ([`features/system/networking/cloudflare`](file:///etc/nixos/features/system/networking/cloudflare/default.nix)).

### 6.1 Der Deployment-Ablauf via `nix run .#sync-cloudflare` (oder `nod switch cloudflare`):
1. **Synthese:** Nix generiert die Soll-Zustands-Spezifikation (`cloudflare-desired-state.json`) deterministisch aus `my.topology` und `my.endpoints`:
   - `@` $\to$ `A` `173.249.22.211` (`cld-edge-01`, `proxied: true`)
   - `edge` $\to$ `A` `173.249.22.211` (`proxied: false` für direct SSH & WireGuard)
   - `ops` $\to$ `A` `37.114.55.91` (`proxied: false` für Telemetrie & WireGuard)
   - `*` $\to$ `CNAME` `edge.vyrx.de` (`proxied: true` für Wildcard-Ingress)
   - Edge-Settings: SSL `strict`, Min-TLS `1.3`, `always_use_https = on`
2. **Secret-Injektion:** Das API-Token wird sicher über SOPS (`infra/cloudflare_api_token`) bezogen.
3. **Idempotenter Abgleich:** Die Sync-Engine [`sync.py`](file:///etc/nixos/features/system/networking/cloudflare/sync.py) vergleicht Ist- und Soll-Zustand über die Cloudflare API v4 und aktualisiert atomar.
4. **Automatisierung:** Auf [`cld-edge-01`](file:///etc/nixos/hosts/cld-edge-01/configuration.nix) läuft zusätzlich ein täglicher Systemd-Timer (`cloudflare-dns-sync.timer`) für kontinuierliche Drift-Erkennung.

---

## 7. Automatische Topologie-Projektion & Kettenreaktion

Sämtliche Devices und Targets werden in der zentralen Topologie-Registry gepflegt:

```nix
my.topology.hosts = {
  # Server & Clients (NixOS)
  hom-srv-01 = { zone = "infra"; ipv4 = "10.10.10.10"; targetType = "nixos"; };
  hom-wrk-01 = { zone = "corp";  ipv4 = "10.10.20.10"; targetType = "nixos"; };
  cld-edge-01 = { zone = "mesh";  ipv4 = "173.249.22.211"; targetType = "nixos"; };

  # Embedded Router & Access Point
  hom-rt-01  = { zone = "infra"; ipv4 = "10.10.10.1";  targetType = "fritzbox"; };
  hom-ap-01  = { zone = "infra"; ipv4 = "10.10.10.20"; targetType = "openwrt"; mac = "00:14:D1:E2:B3:A4"; };
};

my.topology.devices = {
  # Microcontroller & IoT (ESPHome)
  living-room-sensor = { zone = "iot"; ipv4 = "10.10.30.25"; targetType = "esphome"; mac = "24:6F:28:A1:B2:C3"; };
  klipper-toolhead   = { zone = "iot"; ipv4 = "10.10.30.51"; targetType = "esphome"; };
};
```

### Automatische Kettenreaktion beim Deployment:
1. **DHCP:** Der NixOS-Gateway-Dienst auf `hom-srv-01` erzeugt die statische DHCP-Reservierung für `hom-ap-01` und `living-room-sensor`.
2. **DNS (LAN):** Blocky DNS generiert automatisch `hom-rt-01.lan.vyrx.de`, `hom-ap-01.lan.vyrx.de` und `living-room-sensor.lan.vyrx.de`.
3. **DNS (WAN):** Cloudflare GitOps deklariert atomar alle externen Endpoints und Edge-Routing-Ziele.
4. **Firewall:** `nftables` sperrt `living-room-sensor` in die isolierte IoT-Zone (nur Zugriff auf Home Assistant erlaubt).
5. **Monitoring:** Prometheus Blackbox-Exporter beginnt automatisch mit ICMP-Ping-Checks auf alle Targets.

---

## 8. Zusammenfassung & Mehrwert

| Kriterium | Früher (Typisches IoT- & Cloud-Chaos) | nixfiles 2.0 (Agentless GitOps) |
|---|---|---|
| **Router-Verwaltung** | Login ins FRITZ!Box Web-UI, Formular-Klicken | **Deklarativer Soll-Zustand**, abgeglichen via TR-064 |
| **WLAN-Verwaltung** | Login ins TP-Link Web-UI, händisches Tippen | **Deklarative UCI-Dateien**, deployt per `nod switch` |
| **Edge- & DNS-Verwaltung** | Manuelles Klicken im Cloudflare-Dashboard | **Deklarative DNS-Records & TLS**, Sync per Flake-App |
| **Secrets & Passwörter** | Klartext in Web-UIs oder ungesicherten YAMLs | **100% verschlüsselt in SOPS**, zur Laufzeit injiziert |
| **Microcontroller-OTA** | Manuelles Uploaden im ESPHome-Dashboard | **Kompiliert & deployed per Terminal-Befehl** |
| **Tooling** | 5 verschiedene GUIs und Web-Konsolen | **Einheitliches Interface:** `nod switch <target>` / Nix Apps |
| **Desaster Recovery** | Hardware defekt = mühsames Neukonfigurieren | Neues Gerät anschließen $\to$ `nod switch` $\to$ betriebsbereit |
