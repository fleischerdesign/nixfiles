# VYRX Declarative Identity & Access Management Specification

> **Status:** Architecture Blueprint & Implementation Guide  
> **System:** Authentik GitOps Engine (Zero-Touch Provisioning)  
> **Domain:** `auth.vyrx.de`  
> **Design Goals:** Vollständige Reproduzierbarkeit, SOLID-Entkopplung, SOPS Secret-Inversion, Zero-Touch Outposts, Passkey-First Identity.

---

## 0. As-Built Status (2026-09-19) — supersedes older sections

> Diese Sektion beschreibt den **tatsächlich implementierten** Stand. Wo sie älteren Text widerspricht, gilt diese Sektion; §5/§6 sind historisch/illustrativ.

**Blueprint-Pfad (real):** `features/services/authentik/server/blueprints/`
- `00-system/` (Brand), `01-rbac/` (Gruppen + User), `02-flows/` (Recovery, Enrollment, Remember-me, Passkey-Autofill)
- generiert nach `03-apps/`: `proxy-apps-generated.yaml`, `oidc-apps-generated.yaml`, `ldap-outposts-generated.yaml` (Kompilierung in `server/default.nix`)

**Korrekturen gegenüber der ursprünglichen Spezifikation:**

1. **YAML-Tags:** Authentik kennt **kein `!Key`**, nur `!KeyOf` (sowie `!Find`, `!Env`, `!File`, `!Context`, …). Ein unbekanntes Tag bricht schon die Migration `authentik_blueprints.0001_initial` (sie parst jede Blueprint-YAML) → überall `!KeyOf`.
2. **Generierte App-Blueprints:** Authentik entdeckt nur `*.yaml`; JSON kann keine YAML-Tags tragen → Apps werden als **getaggtes YAML** emittiert (`toBlueprintYaml`, Sentinel + `sed`). Pflichtfelder: `authorization_flow` **und** `invalidation_flow`; `redirect_uris` als Objekte `{matching_mode, url}`.
3. **Reihenfolge:** Blueprint-Apply ist **nicht** geordnet (offizielle Doku) → Abhängigkeiten explizit via `authentik_blueprints.metaapplyblueprint` (Default-Provider-Flows, RBAC-Gruppe).
4. **Forward-Auth:** zentraler **Embedded Outpost** des Authentik-Servers; Caddy-Ziel via `my.features.services.authentik.server.embeddedOutpostAddress` (`127.0.0.1:9055` lokal, `10.10.100.1:9055` remote). Kein eigener Proxy-Outpost/-Token mehr.
5. **LDAP-Outposts:** **ein Outpost pro Host** mit eigenem Service-Account + Token (`intent = "api"`), Key via `!File` aus per-Host-SOPS-Secret `services/authentik/outposts/<host>-ldap-token`; Rolle mit globalen Reads (`view_user`, `view_group`, `add_event`) plus Objekt-Permissions an der **benannten Rolle** (nicht der Managed-Role); LDAP-Provider + Application; Listen `389/636`.
6. **Bootstrap/Setup:** kein OOBE. `AUTHENTIK_BOOTSTRAP_PASSWORD` (in `services/authentik/core_env`) triggert `system/bootstrap.yaml` → legt `akadmin` an und setzt `setup = true`. `akadmin` = Break-Glass (`authentik Admins`); `infra-admins` bleibt separater Cluster-Admin.
7. **Self-Service:** Email-Recovery (`flow_recovery` am Brand), Invitation-Enrollment, Passkey-Autofill (Conditional UI), Remember-me (`session_duration = days=7`, `remember_me_offset = days=30`). Keine erzwungenen Passwort-Policies.
8. **Worker:** `AUTHENTIK_WORKER__THREADS=1` (verhindert den `authentik_flows_stage`-Deadlock beim frischen Bootstrap); Worker-Metrics auf `9301` (Server `9300`).
9. **Apply-Pfad:** Änderungen gehen über das **Host-Closure** (`nixos-rebuild` bzw. `nod switch cld-edge-01`); `nodTargets.authentik` wurde entfernt. Rollout/Runbook: **`operations.md`**.

---

## 1. Leitphilosophie & Das GitOps-Axiom

In klassischen Identitätsmanagement-Systemen (IdP) führt die Konfiguration über das Web-UI („ClickOps“) unweigerlich zu **Konfigurationsdrift** und **fehlender Disaster-Recovery-Fähigkeit**. Geht die relationale Datenbank verloren, müssen Dutzende OIDC-Clients, Rollen, Outpost-Tokens und Proxy-Weiterleitungen stundenlang händisch rekonstruiert werden.

### Das GitOps-Axiom für nixfiles 2.0:
> **Die PostgreSQL-Datenbank von Authentik ist ein flüchtiger Laufzeitzustand.**  
> Die gesamte Konfiguration (Provider, Outposts, Gruppen, Service-Accounts, RBAC und Applikations-Bindings) wird als deklarativer Code im Git-Repository versioniert und beim Bootstrapping **idempotent** angewendet.

---

## 2. SOLID-Modellierung der Identitäts-Architektur

Die Architektur folgt streng den Prinzipien objektorientierten und komponentenorientierten Systemdesigns:

```
                            ┌────────────────────────────────────────┐
                            │    my.topology & secrets.yaml (SSOT)   │
                            └───────────────────┬────────────────────┘
                                                │
                                                ▼
                            ┌────────────────────────────────────────┐
                            │   features/services/authentik/         │
                            │   blueprints/                          │
                            └───────┬───────────┬────────────┬───────┘
                                    │           │            │
            ┌───────────────────────┘           │            └───────────────────────┐
            ▼                                   ▼                                    ▼
┌───────────────────────┐           ┌───────────────────────┐            ┌───────────────────────┐
│  02-rbac.yaml         │           │  04-outposts.yaml     │            │  05-apps/*.yaml       │
│  (Rollen & Gruppen)   │           │  (LDAP & Proxy Outp.) │            │  (OIDC & Forward-Auth)│
└───────────────────────┘           └───────────────────────┘            └───────────────────────┘
            │                                   │                                    │
            └───────────────────────────────────┼────────────────────────────────────┘
                                                ▼
                                    ┌───────────────────────┐
                                    │   Authentik Core      │ (cld-edge-01)
                                    │   State Plane (DB)    │
                                    └───────────────────────┘
```

1. **Single Responsibility Principle (SRP):**
   * Das Authentik-Core-Modul verwaltet die Laufzeit (Web-Server, Worker, DB).
   * Feature-Module (z. B. Grafana, Sonarr) deklarieren rein ihren Authentifizierungs-Bedarf.
   * Blueprints bündeln die deklarative Übersetzung in Authentik-Datenmodelle.
2. **Open/Closed Principle (OCP):**
   * Das System ist offen für neue Dienste: Ein neuer Dienst bringt sein eigenes Provider-Blueprint mit. Die bestehenden Core-Flows und Outposts bleiben unberührt.
3. **Dependency Inversion Principle (DIP):**
   * Weder Authentik noch die Outposts hängen von interaktiv erzeugten Zufallstokens ab. Beide hängen von der gemeinsamen Abstraktion ab: den in SOPS deklarierten Secrets.
4. **Don't Repeat Yourself (DRY):**
   * Jeder OIDC-Client, jeder Port und jede URL speist sich aus `my.topology` und `secrets.yaml`.

---

## 3. Die kryptografische Trennung: Mensch vs. Maschine

Ein Kernproblem deklarativer Identitätsverwaltung ist der Unterschied zwischen statischen Berechtigungsstrukturen und asymmetrischen Hardware-Schlüsseln.

### 3.1 Service-Accounts (Maschinen-Identitäten) $\to$ 100% Deklarativ
* Für Daemons, Outposts, CI/CD-Pipelines und APIs.
* Werden vollständig mit statischem Token im Blueprint angelegt:
  $$\text{ServiceAccount} = (\text{Username}, \text{Role}, \text{Token}_{\text{SOPS}})$$
* **Zero-Touch:** Authentik liest den Token via `!Env` aus dem SOPS-Environment ein. Der anbindende Dienst erhält exakt denselben Token. Es existiert null manueller Einrichtungsaufwand.

### 3.2 Menschliche Identitäten $\to$ Hybrides Berechtigungsmodell
* **Deklarativer Anteil (Die Identitäts-Hülle):**
  * Benutzername, E-Mail-Adresse, Anzeigename und Gruppenzugehörigkeit (`infra-admins`, `family`, `media-users`) werden fest im Blueprint deklariert.
* **Interaktiver Anteil (Die FIDO2/Passkey-Zeremonie):**
  * Ein FIDO2/WebAuthn-Passkey kann **mathematisch nicht vorab in YAML deklariert werden**, da er hardwaregebunden im Secure Element (YubiKey, Apple Touch ID, Windows Hello) über eine interaktive kryptografische Challenge-Response-Zeremonie erzeugt wird.
  * **Ablauf:** Der Benutzer existiert sofort im System mit allen Rechten. Beim Erst-Login registriert er seinen Passkey browsergestützt über den standardisierten WebAuthn-Flow.

---

## 4. Token-Inversion Pattern (Lösung des Outpost Henne-Ei-Problems)

Bisheriges Antipattern: Outpost im UI erstellen $\to$ Authentik erzeugt Token $\to$ Admin kopiert Token in SOPS $\to$ NixOS liest SOPS.

### Das Token-Inversion Pattern:
Der Datenfluss wird umgedreht. **SOPS ist die alleinige Quelle der Wahrheit (SSOT):**

```
                   ┌────────────────────────────────────────┐
                   │          secrets/secrets.yaml          │
                   │  services.authentik.ldap_outpost_token │
                   └───────────────────┬────────────────────┘
                                       │
                     ┌─────────────────┴─────────────────┐
                     ▼                                   ▼
          ┌─────────────────────┐             ┌─────────────────────┐
          │   Authentik Core    │             │   LDAP Outpost      │
          │   EnvironmentFile   │             │   EnvironmentFile   │
          └──────────┬──────────┘             └──────────┬──────────┘
                     │                                   │
                     ▼                                   ▼
          Blueprint Engine                    Outpost Daemon
          Token Key: !Env TOKEN               AUTHENTIK_TOKEN: $TOKEN
                     │                                   │
                     └───────────────► ◄─────────────────┘
                            Kollisionsfreier Handshake
```

1. In `secrets/secrets.yaml` existiert ein deterministischer Token `services.authentik.ldap_outpost_token`.
2. `systemd.services.authentik-server` injiziert das Secret als `AUTHENTIK_OUTPOST_LDAP_TOKEN`.
3. Das Blueprint erzeugt das Token-Objekt mit:
   ```yaml
   key: "!Env AUTHENTIK_OUTPOST_LDAP_TOKEN"
   ```
4. `systemd.services.authentik-outpost-ldap` startet mit demselben Token aus SOPS.
5. Beide Dienste verbinden sich beim ersten Systemstart ohne jegliche Benutzerinteraktion.

---

## 5. Hierarchische Blueprint-Struktur

Die Konfiguration wird unter `features/services/authentik/server/blueprints/` modular abgelegt:

```
features/services/authentik/server/blueprints/
├── 00-system/
│   ├── brand.yaml           # Titel, Design-Tokens aus design.md, Favicon
│   └── flows-core.yaml      # Exportierte Passkey- & Invalidation-Flows
├── 01-rbac/
│   ├── groups.yaml          # Rollen (infra-admins, media, guest)
│   └── service-users.yaml   # Basis-Identitäten
├── 02-outposts/
│   ├── embedded.yaml        # Interne Proxy-Outpost-Definition
│   └── ldap.yaml            # LDAP Outpost Definition & Token-Binding
└── 03-apps/
    ├── monitoring.yaml      # Grafana (OIDC)
    ├── media.yaml           # Jellyfin, Jellyseerr (OIDC)
    └── arr-stack.yaml       # Sonarr, Radarr, Prowlarr (Forward-Auth Proxy)
```

---

## 6. Kanonische Blueprint-Spezifikationen

### 6.1 RBAC & Gruppen (`01-rbac/groups.yaml`)
```yaml
version: 1
metadata:
  name: "vyrx-rbac-groups"
entries:
  - model: authentik_core.group
    id: group_infra_admins
    identifiers:
      name: "infra-admins"
    attrs:
      is_superuser: true
      attributes:
        description: "Cluster Administrators (Root Access)"

  - model: authentik_core.group
    id: group_media_users
    identifiers:
      name: "media-users"
    attrs:
      is_superuser: false
      attributes:
        description: "Access to Media Streaming & Requests"

  - model: authentik_core.user
    id: user_primary_admin
    identifiers:
      username: "philipp"
    attrs:
      name: "Philipp"
      email: "philipp@vyrx.de"
      groups:
        - !KeyOf group_infra_admins
        - !KeyOf group_media_users
```

### 6.2 OIDC Provider Beispiel: Grafana (`03-apps/monitoring.yaml`)
```yaml
version: 1
metadata:
  name: "vyrx-app-grafana"
entries:
  - model: authentik_providers_oauth2.oauth2provider
    id: provider_grafana
    identifiers:
      name: "Grafana OIDC Provider"
    attrs:
      client_id: "grafana"
      client_secret: "!Env GRAFANA_OIDC_CLIENT_SECRET"
      authorization_flow: "!Find [authentik_flows.flow, [slug, default-provider-authorization-explicit-consent]]"
      redirect_uris:
        - "https://grafana.vyrx.de/login/generic_oauth"
      sub_mode: "hashed_user_id"
      include_claims_in_id_token: true
      signing_key: "!Find [authentik_crypto.certificatekeypair, [name, authentik Self-signed Certificate]]"

  - model: authentik_core.application
    identifiers:
      slug: "grafana"
    attrs:
      name: "Grafana"
      provider: !KeyOf provider_grafana
      meta_launch_url: "https://grafana.vyrx.de"
      group: "Observability"
      open_in_new_tab: true
```

### 6.3 Forward-Auth Proxy Provider Beispiel: Sonarr (`03-apps/arr-stack.yaml`)
```yaml
version: 1
metadata:
  name: "vyrx-app-sonarr"
entries:
  - model: authentik_providers_proxy.proxyprovider
    id: provider_sonarr
    identifiers:
      name: "Sonarr Forward-Auth"
    attrs:
      mode: "forward_single"
      external_host: "https://sonarr.lan.vyrx.de"
      authorization_flow: "!Find [authentik_flows.flow, [slug, default-provider-authorization-explicit-consent]]"

  - model: authentik_core.application
    identifiers:
      slug: "sonarr"
    attrs:
      name: "Sonarr"
      provider: !KeyOf provider_sonarr
      group: "Arr Stack"

  - model: authentik_policies_expression.expressionpolicy
    id: policy_admins_only
    identifiers:
      name: "Admins Only"
    attrs:
      expression: |
        return ak_is_group_member(request.user, name="infra-admins")

  - model: authentik_policies.policybinding
    identifiers:
      target: !KeyOf provider_sonarr
      policy: !KeyOf policy_admins_only
      order: 0
    attrs:
      enabled: true
```

### 6.4 LDAP Outpost & Token Automation (`02-outposts/ldap.yaml`)
```yaml
version: 1
metadata:
  name: "vyrx-outpost-ldap"
entries:
  - model: authentik_core.user
    id: sa_ldap
    identifiers:
      username: "ak-outpost-ldap"
    attrs:
      name: "Service Account LDAP Outpost"
      type: "service_account"

  - model: authentik_core.token
    identifiers:
      identifier: "outpost-ldap-token"
    attrs:
      intent: "app_password"
      user: !KeyOf sa_ldap
      key: "!Env AUTHENTIK_OUTPOST_LDAP_TOKEN"

  - model: authentik_providers_ldap.ldapprovider
    id: provider_ldap_main
    identifiers:
      name: "VYRX LDAP Provider"
    attrs:
      base_dn: "DC=vyrx,DC=de"
      search_group: !KeyOf group_infra_admins

  - model: authentik_outposts.outpost
    identifiers:
      name: "vyrx-ldap-outpost"
    attrs:
      type: "ldap"
      service_connection: null # Standalone / Managed via NixOS
      providers:
        - !KeyOf provider_ldap_main
      config:
        authentik_host: "https://auth.vyrx.de"
```

---

## 7. Deklarative Integration in NixOS

Das Server-Modul in [features/services/authentik/server/default.nix](file:///etc/nixos/features/services/authentik/server/default.nix) wird um die automatische Blueprint-Engine erweitert:

```nix
# features/services/authentik/server/default.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.my.features.services.authentik.server;
  blueprintsDir = ./blueprints;
in
{
  config = lib.mkIf cfg.enable {
    # 1. Environment mit SOPS Secrets für Blueprints anreichern
    sops.templates."authentik-core.env".content = ''
      AUTHENTIK_SECRET_KEY=${config.sops.placeholder."services/authentik/secret_key"}
      AUTHENTIK_OUTPOST_LDAP_TOKEN=${config.sops.placeholder."services/authentik/ldap_outpost_token"}
      GRAFANA_OIDC_CLIENT_SECRET=${config.sops.placeholder."observability/grafana/oidc_client_secret"}
    '';

    # 2. Systemd Service deklariert Blueprint-Verzeichnis
    systemd.services.authentik-server = {
      serviceConfig = {
        Environment = [
          "AUTHENTIK_BLUEPRINTS_DIR=${blueprintsDir}"
        ];
        EnvironmentFile = [
          config.sops.templates."authentik-core.env".path
        ];
      };
    };

    # 3. Flake Check zur Validierung der Blueprints (Compile-Time Guardrail)
    # Stellt sicher, dass alle YAML-Dateien syntaktisch valide sind
  };
}
```

---

## 8. Desaster-Recovery Matrix (Zero-Touch Wiederanlauf)

| Szenario | Früher (UI-ClickOps) | Mit Declarative Blueprints (nixfiles 2.0) |
|---|---|---|
| **Datenbankverlust (Postgres Crash)** | Tagelanges mühsames Neuklicken aller 20 Clients, Tokens und Outposts | **Vollautomatisch in < 60s:** NixOS bootet, startet Authentik, wendet alle Blueprints idempotent an $\to$ alle Apps wieder online. |
| **Neuer Service hinzufügen** | Admin öffnet Browser, klickt Provider, kopiert Redirect-URI, erzeugt Secret | Ein Git-Commit (`03-apps/<service>.yaml`). Deploy via `nod switch`. Fertig. |
| **Outpost Deployment** | Manuelle Token-Generierung im UI, Copy-Paste in SOPS | Zero-Touch. Outpost startet und authentifiziert sich über das vordefinierte SOPS-Secret. |
| **Audit-Fähigkeit** | Wer darf was? Nur in PostgreSQL-Tabellen ersichtlich | **100% Git-Audit:** Jede Berechtigungsänderung ist ein Git-Commit mit PR-Review. |

---

## 9. Zusammenfassung

Mit dieser Spezifikation wird Authentik von einer isolierten Web-Applikation zu einem **vollwertigen, deklarativen Baustein von nixfiles 2.0**. Das Zusammenspiel aus **SOPS Secret-Inversion**, **Blueprints** und **Nix-Modulen** garantiert maximale Ausfallsicherheit und absolute Wartungsfreiheit.
