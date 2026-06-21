# Refactoring Aktionsplan - Phase 2 (Bereinigung & Kapselung)

Dieser Plan beschreibt Schritt für Schritt, wie verbleibende Kopplungen und hardcodierte Domains (insbesondere die Domain `ancoris.ovh`) in den NixOS-Feature-Modulen von `/workspace/dev` modularisiert werden.

Jeder Schritt ist vollkommen abwärtskompatibel, lässt sich separat committen und validieren.

---

## Übersicht der Schritte

| Nr. | Schritt | Aufwand | Risiko | Ziel-Dateien |
|---|---|---|---|---|
| 1 | CrowdSec Master Host konfigurierbar machen | Klein | Gering | `features/services/crowdsec/default.nix` |
| 2 | Authentik Outpost Port in Caddy parametrisieren | Klein | Gering | `features/services/caddy/default.nix` |
| 3 | Hartcodierte Domains in 11 Services entkoppeln | Mittel | Gering | Siehe Schritt 3 Details |
| 4 | Fehlende Description-Felder aus Phase 1 ergänzen | Klein | Gering | `features/services/sabnzbd/default.nix` |

---

## Schritt 1: CrowdSec Master Host konfigurierbar machen
Entkoppelt die IP des CrowdSec LAPI-Servers vom festen Hostnamen `mackaye`.

*   **Datei:** [features/services/crowdsec/default.nix](file:///workspace/dev/features/services/crowdsec/default.nix)
*   **Vorher:**
    ```nix
    let
      cfg = config.my.features.services.crowdsec;
      isMaster = cfg.role == "master";
      # Use topology host definitions for IPs
      masterIP = config.my.features.system.networking.topology.hosts.mackaye.tailscaleIp;
    in
    {
      options.my.features.services.crowdsec = {
        enable = lib.mkEnableOption "CrowdSec IPS";
        role = lib.mkOption {
          type = lib.types.enum [
            "master"
            "agent"
          ];
          default = "agent";
          description = "Role of this host: master (LAPI server) or agent (client).";
        };
        excludeLogPatterns = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Regex patterns for log files to exclude from acquisition.";
        };
      };
    ```
*   **Nachher:**
    ```nix
    let
      cfg = config.my.features.services.crowdsec;
      isMaster = cfg.role == "master";
      # Use topology host definitions for IPs
      masterIP = config.my.features.system.networking.topology.hosts.${cfg.masterHost}.tailscaleIp;
    in
    {
      options.my.features.services.crowdsec = {
        enable = lib.mkEnableOption "CrowdSec IPS";
        masterHost = lib.mkOption {
          type = lib.types.str;
          default = "mackaye";
          description = "The name of the CrowdSec master host (LAPI server) in the topology.";
        };
        role = lib.mkOption {
          type = lib.types.enum [
            "master"
            "agent"
          ];
          default = "agent";
          description = "Role of this host: master (LAPI server) or agent (client).";
        };
        excludeLogPatterns = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Regex patterns for log files to exclude from acquisition.";
        };
      };
    ```
*   **Testen:** `nix flake check` ausführen.

---

## Schritt 2: Authentik Outpost Port in Caddy parametrisieren
Macht die Forward-Auth-Outpost-Adresse im Caddy-Modul über Optionen konfigurierbar.

*   **Datei:** [features/services/caddy/default.nix](file:///workspace/dev/features/services/caddy/default.nix)
*   **Vorher:**
    ```nix
      options.my.features.services.caddy = {
        enable = lib.mkEnableOption "Caddy Web Server";

        baseDomain = lib.mkOption {
          type = lib.types.str;
          description = "Base domain for exposed services (e.g. fls.ancoris.ovh)";
        };
      };
    ```
    (und `127.0.0.1:9000` hardcodiert in den Proxy/Forward-Auth Blöcken im Caddyfile)
*   **Nachher:**
    ```nix
      options.my.features.services.caddy = {
        enable = lib.mkEnableOption "Caddy Web Server";

        baseDomain = lib.mkOption {
          type = lib.types.str;
          description = "Base domain for exposed services (e.g. fls.ancoris.ovh)";
        };

        authentikOutpostAddress = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1:9000";
          description = "Local socket address of the Authentik outpost proxy.";
        };
      };
    ```
    (und im Caddyfile-Block wird `127.0.0.1:9000` durch `${cfg.authentikOutpostAddress}` ersetzt)
*   **Testen:** `nix flake check`

---

## Schritt 3: Hartcodierte Domains in 11 Services entkoppeln

Jedes der 11 folgenden Service-Module wird um entsprechende Optionen erweitert und nutzt diese, um hartcodierte Instanzen von `ancoris.ovh` zu ersetzen.

### 3.1 Vaultwarden
*   **Datei:** [features/services/vaultwarden/default.nix](file:///workspace/dev/features/services/vaultwarden/default.nix)
*   **Diff-Entwurf:** Exponiert `domain` (Default: `"vault.ancoris.ovh"`) und `ssoAuthority` (Default: `"https://auth.ancoris.ovh/application/o/vaultwarden/"`).
    ```nix
      options.my.features.services.vaultwarden = {
        enable = lib.mkEnableOption "Vaultwarden";
        domain = lib.mkOption {
          type = lib.types.str;
          default = "vault.ancoris.ovh";
          description = "FQDN for Vaultwarden.";
        };
        ssoAuthority = lib.mkOption {
          type = lib.types.str;
          default = "https://auth.ancoris.ovh/application/o/vaultwarden/";
          description = "OIDC Issuer/Authority URL for single sign-on.";
        };
      };
    ```

### 3.2 Homarr
*   **Datei:** [features/services/homarr/default.nix](file:///workspace/dev/features/services/homarr/default.nix)
*   **Diff-Entwurf:** Exponiert `domain` (Default: `"ancoris.ovh"`), `ssoAuthority` (Default: `"https://auth.ancoris.ovh/application/o/homarr/"`), `ssoAuthorizeUrl` (Default: `"https://auth.ancoris.ovh/application/o/authorize"`) und `ssoLogoutRedirectUrl` (Default: `"https://auth.ancoris.ovh/application/o/homarr/end-session/"`).
    ```nix
      options.my.features.services.homarr = {
        enable = lib.mkEnableOption "Homarr Dashboard";
        domain = lib.mkOption {
          type = lib.types.str;
          default = "ancoris.ovh";
          description = "Domain name for Homarr.";
        };
        ssoAuthority = lib.mkOption {
          type = lib.types.str;
          default = "https://auth.ancoris.ovh/application/o/homarr/";
          description = "Authentik SSO authority issuer.";
        };
        ssoAuthorizeUrl = lib.mkOption {
          type = lib.types.str;
          default = "https://auth.ancoris.ovh/application/o/authorize";
          description = "Authentik OIDC authorize endpoint.";
        };
        ssoLogoutRedirectUrl = lib.mkOption {
          type = lib.types.str;
          default = "https://auth.ancoris.ovh/application/o/homarr/end-session/";
          description = "SSO Logout redirect URL.";
        };
      };
    ```

### 3.3 Linkwarden
*   **Datei:** [features/services/linkwarden/default.nix](file:///workspace/dev/features/services/linkwarden/default.nix)
*   **Diff-Entwurf:** Exponiert `domain` (Default: `"linkwarden.mky.ancoris.ovh"`) und `ssoAuthority` (Default: `"https://auth.ancoris.ovh/application/o/linkwarden"`).
    ```nix
      options.my.features.services.linkwarden = {
        enable = lib.mkEnableOption "Linkwarden";
        domain = lib.mkOption {
          type = lib.types.str;
          default = "linkwarden.mky.ancoris.ovh";
          description = "Domain name for Linkwarden.";
        };
        ssoAuthority = lib.mkOption {
          type = lib.types.str;
          default = "https://auth.ancoris.ovh/application/o/linkwarden";
          description = "SSO Authority URL for Linkwarden.";
        };
      };
    ```

### 3.4 Mail (Stalwart)
*   **Datei:** [features/services/mail/default.nix](file:///workspace/dev/features/services/mail/default.nix)
*   **Diff-Entwurf:** Exponiert `domain` (Default: `"mail.ancoris.ovh"`), `baseDomain` (Default: `"ancoris.ovh"`) und `ssoAuthority` (Default: `"https://auth.ancoris.ovh/application/o/stalwart/"`).
    ```nix
      options.my.features.services.mail = {
        enable = lib.mkEnableOption "Stalwart Mail Server";
        domain = lib.mkOption {
          type = lib.types.str;
          default = "mail.ancoris.ovh";
          description = "FQDN of the mail server.";
        };
        baseDomain = lib.mkOption {
          type = lib.types.str;
          default = "ancoris.ovh";
          description = "Base domain name.";
        };
        ssoAuthority = lib.mkOption {
          type = lib.types.str;
          default = "https://auth.ancoris.ovh/application/o/stalwart/";
          description = "SSO Authority/Issuer URL.";
        };
      };
    ```
    (und im deployment-script wird `/mail.ancoris.ovh/` durch `/${cfg.domain}/` ersetzt)

### 3.5 Mealie
*   **Datei:** [features/services/mealie/default.nix](file:///workspace/dev/features/services/mealie/default.nix)
*   **Diff-Entwurf:** Exponiert `smtpFromEmail` (Default: `"noreply@ancoris.ovh"`) und `ssoConfigurationUrl` (Default: `"https://auth.ancoris.ovh/application/o/mealie/.well-known/openid-configuration"`).
    ```nix
      options.my.features.services.mealie = {
        enable = lib.mkEnableOption "Mealie Recipe Manager";
        smtpFromEmail = lib.mkOption {
          type = lib.types.str;
          default = "noreply@ancoris.ovh";
          description = "From address for SMTP outgoing mails.";
        };
        ssoConfigurationUrl = lib.mkOption {
          type = lib.types.str;
          default = "https://auth.ancoris.ovh/application/o/mealie/.well-known/openid-configuration";
          description = "OIDC discovery configuration endpoint URL.";
        };
      };
    ```

### 3.6 Grafana
*   **Datei:** [features/services/monitoring/grafana/default.nix](file:///workspace/dev/features/services/monitoring/grafana/default.nix)
*   **Diff-Entwurf:** Exponiert `domain` (Default: `"grafana.mky.ancoris.ovh"`), `ssoAuthority` (Default: `"https://auth.ancoris.ovh/application/o"`) und `ntfyAlertUrl` (Default: `"https://ntfy.mky.ancoris.ovh/grafana-alerts?template=grafana"`).
    ```nix
      options.my.features.services.monitoring.grafana = {
        enable = lib.mkEnableOption "Grafana Dashboard";
        domain = lib.mkOption {
          type = lib.types.str;
          default = "grafana.mky.ancoris.ovh";
          description = "FQDN of the Grafana instance.";
        };
        ssoAuthority = lib.mkOption {
          type = lib.types.str;
          default = "https://auth.ancoris.ovh/application/o";
          description = "Base SSO authority URL.";
        };
        ntfyAlertUrl = lib.mkOption {
          type = lib.types.str;
          default = "https://ntfy.mky.ancoris.ovh/grafana-alerts?template=grafana";
          description = "Ntfy webhook URL for Grafana alerts.";
        };
      };
    ```

### 3.7 Paperless
*   **Datei:** [features/services/paperless/default.nix](file:///workspace/dev/features/services/paperless/default.nix)
*   **Diff-Entwurf:** Exponiert `ssoServerUrl` (Default: `"https://auth.ancoris.ovh/application/o/paperless"`).
    ```nix
      options.my.features.services.paperless = {
        enable = lib.mkEnableOption "Paperless-ngx Document Management";
        ssoServerUrl = lib.mkOption {
          type = lib.types.str;
          default = "https://auth.ancoris.ovh/application/o/paperless";
          description = "OIDC Server URL connection.";
        };
      };
    ```

### 3.8 Plausible
*   **Datei:** [features/services/plausible/default.nix](file:///workspace/dev/features/services/plausible/default.nix)
*   **Diff-Entwurf:** Exponiert `domain` (Default: `"plausible.mky.ancoris.ovh"`).
    ```nix
      options.my.features.services.plausible = {
        enable = lib.mkEnableOption "Plausible Analytics";
        domain = lib.mkOption {
          type = lib.types.str;
          default = "plausible.mky.ancoris.ovh";
          description = "Domain name for Plausible instance.";
        };
      };
    ```

### 3.9 Attic (Client)
*   **Datei:** [features/services/attic/client/default.nix](file:///workspace/dev/features/services/attic/client/default.nix)
*   **Diff-Entwurf:** Exponiert `endpoint` (Default: `"https://cache.rls.ancoris.ovh"`).
    ```nix
      options.my.features.services.attic.client = {
        ...
        endpoint = lib.mkOption {
          type = lib.types.str;
          default = "https://cache.rls.ancoris.ovh";
          description = "Attic cache server URL.";
        };
      };
    ```

### 3.10 Attic (Server)
*   **Datei:** [features/services/attic/server/default.nix](file:///workspace/dev/features/services/attic/server/default.nix)
*   **Diff-Entwurf:** Exponiert `domain` (Default: `"cache.rls.ancoris.ovh"`).
    ```nix
      options.my.features.services.attic.server = {
        enable = lib.mkEnableOption "Attic Nix binary cache server";
        domain = lib.mkOption {
          type = lib.types.str;
          default = "cache.rls.ancoris.ovh";
          description = "Domain of the cache server.";
        };
      };
    ```

### 3.11 Authentik Server
*   **Datei:** [features/services/authentik/server/default.nix](file:///workspace/dev/features/services/authentik/server/default.nix)
*   **Diff-Entwurf:** Exponiert `domain` (Default: `"auth.ancoris.ovh"`).
    ```nix
      options.my.features.services.authentik.server = {
        enable = lib.mkEnableOption "Authentik Identity Provider (Server)";
        domain = lib.mkOption {
          type = lib.types.str;
          default = "auth.ancoris.ovh";
          description = "FQDN of the Authentik identity server.";
        };
      };
    ```

### 3.12 CouchDB
*   **Datei:** [features/services/couchdb/default.nix](file:///workspace/dev/features/services/couchdb/default.nix)
*   **Diff-Entwurf:** Exponiert `domain` (Default: `"couchdb.mky.ancoris.ovh"`).
    ```nix
      options.my.features.services.couchdb = {
        enable = lib.mkEnableOption "CouchDB Server";
        domain = lib.mkOption {
          type = lib.types.str;
          default = "couchdb.mky.ancoris.ovh";
          description = "Domain of the CouchDB service.";
        };
      };
    ```

---

## Schritt 4: Fehlende Description-Felder aus Phase 1 ergänzen
Fügt allen in Phase 1 neu erstellten Optionen aussagekräftige `description`-Felder hinzu, um die IDE-Autovervollständigung (via Nix LSP/nil) zu unterstützen.

*   **Datei:** [features/services/sabnzbd/default.nix](file:///workspace/dev/features/services/sabnzbd/default.nix)
*   **Vorher:**
    ```nix
        server = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Configure default Usenet server connection.";
          };
          name = lib.mkOption {
            type = lib.types.str;
            default = "Newsgroup Ninja";
          };
          host = lib.mkOption {
            type = lib.types.str;
            default = "news.newsgroup.ninja";
          };
          port = lib.mkOption {
            type = lib.types.int;
            default = 563;
          };
          ssl = lib.mkOption {
            type = lib.types.bool;
            default = true;
          };
          connections = lib.mkOption {
            type = lib.types.int;
            default = 50;
          };
          username = lib.mkOption {
            type = lib.types.str;
            default = "Butchey";
          };
        };
    ```
*   **Nachher:**
    ```nix
        server = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Configure default Usenet server connection.";
          };
          name = lib.mkOption {
            type = lib.types.str;
            default = "Newsgroup Ninja";
            description = "Friendly display name of the Usenet server.";
          };
          host = lib.mkOption {
            type = lib.types.str;
            default = "news.newsgroup.ninja";
            description = "Usenet server hostname.";
          };
          port = lib.mkOption {
            type = lib.types.int;
            default = 563;
            description = "Usenet server connection port.";
          };
          ssl = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable SSL/TLS for Usenet server connection.";
          };
          connections = lib.mkOption {
            type = lib.types.int;
            default = 50;
            description = "Number of concurrent connections to the Usenet server.";
          };
          username = lib.mkOption {
            type = lib.types.str;
            default = "Butchey";
            description = "Usenet server account username.";
          };
        };
    ```
*   **Testen:** `nix flake check`
