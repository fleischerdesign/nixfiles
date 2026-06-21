# NixOS Refactoring Aktionsplan

Dieser Aktionsplan beschreibt Schritt für Schritt, wie die Modularität, SOLID-Prinzipien, DRY-Qualität und Robustheit der NixOS-Flake-Konfiguration in `/workspace/dev` verbessert werden können.

## Allgemeine Richtlinien
*   **Keine unmittelbaren Funktionsänderungen:** Jeder Schritt führt neue Optionen mit abwärtskompatiblen Default-Werten ein, so dass der Status Quo unberührt bleibt.
*   **Commit & Deploy pro Schritt:** Jeder Schritt kann einzeln committet, via `nix flake check` validiert und risikofrei deployt werden.
*   **Rollback:** Bei Fehlern reicht ein `git reset --hard HEAD~1` und ein erneuter Deploy.

---

## Übersicht der Schritte (Priorisiert nach Risiko & Aufwand)

| Nr. | Schritt | Aufwand | Risiko | Abhängigkeiten |
|---|---|---|---|---|
| 1 | Safe-Guard in `lib/helper.nix` für User-Lookup | Klein | Sehr gering | Keine |
| 2 | Bluetooth-Konfiguration in Feature auslagern | Klein | Gering | Keine |
| 3 | Niri Wallpaper-Pfad in Store-Pfad umwandeln | Klein | Gering | Keine |
| 4 | Niri Multi-Monitor-Konfiguration entkoppeln | Klein | Gering | Keine |
| 5 | Authentik Outpost Proxy konfigurierbar machen | Klein | Gering | Keine |
| 6 | Robustheit von `hermes-webui` gegen fehlenden Agenten sichern | Klein | Gering | Keine |
| 7 | Hermes-Agent URLs und Chat-ID entkoppeln | Mittel | Gering | Keine |
| 8 | Rollen-Refactoring (`base.nix` einführen) | Mittel | Mittel | Schritt 1 |
| 9 | Statische IP-Konfiguration (Server) in Feature modularisieren | Mittel | Mittel | Keine |
| 10| SABnzbd Usenet-Konfiguration & Pfade entkoppeln | Mittel | Gering | Keine |

---

## Schritt 1: Safe-Guard in `lib/helper.nix` für User-Lookup
Ermöglicht das Hinzufügen von System-Benutzern, die (noch) nicht in `lib/users.nix` gepflegt sind, ohne die Evaluation zu crashen.

*   **Machbarkeit:** Sofort commit- und deploybar. Vollständig rückwärtskompatibel.
*   **Zeit/Mühe:** Klein (~10 Minuten)
*   **Risiko:** Keine.
*   **Konkreter Code-Diff:**
    *   **Datei:** `lib/helper.nix`
    ```diff
    -      nixosUsers = lib.listToAttrs (
    -        map (user: {
    -          inherit (user) name;
    -          value = {
    -            isNormalUser = true;
    -            inherit (userLib.${user.name}) description;
    -            extraGroups =
    -              user.extraGroups or [
    -                "networkmanager"
    -                "wheel"
    -              ];
    -            openssh.authorizedKeys.keys = userLib.${user.name}.sshKeys;
    -          };
    -        }) users
    -      );
    +      nixosUsers = lib.listToAttrs (
    +        map (user: {
    +          inherit (user) name;
    +          value = {
    +            isNormalUser = true;
    +            description = (userLib.${user.name} or { description = "User ${user.name}"; }).description or "User ${user.name}";
    +            extraGroups =
    +              user.extraGroups or [
    +                "networkmanager"
    +                "wheel"
    +              ];
    +            openssh.authorizedKeys.keys = (userLib.${user.name} or { sshKeys = [ ]; }).sshKeys or [ ];
    +          };
    +        }) users
    +      );
    ```
*   **Teststrategie:**
    1. Temporär in `flake.nix` einen Test-User `{ name = "testuser"; }` eintragen.
    2. `nix flake check` ausführen. Ohne Fix crashed der Build, mit Fix läuft er durch.

---

## Schritt 2: Bluetooth-Konfiguration in Feature auslagern
Entfernt das kopierte Bluetooth-Konfigurations-Snippet aus den Host-Verzeichnissen von Yorke und Jello.

*   **Machbarkeit:** Einzeln deploybar.
*   **Zeit/Mühe:** Klein (~15 Minuten)
*   **Risiko:** Gering (Bluetooth-Verbindungsprobleme bei Tippfehlern).
*   **Konkreter Code-Diff:**
    *   **Neue Datei:** `features/system/bluetooth/default.nix`
    ```nix
    { config, lib, pkgs, ... }:
    let
      cfg = config.my.features.system.bluetooth;
    in
    {
      options.my.features.system.bluetooth = {
        enable = lib.mkEnableOption "Bluetooth support with audio optimizations";
      };

      config = lib.mkIf cfg.enable {
        hardware.bluetooth = {
          enable = true;
          powerOnBoot = lib.mkDefault true;
          settings = {
            General = {
              Enable = "Source,Sink,Media,Socket";
            };
          };
        };
      };
    }
    ```
    *   **Datei:** `hosts/yorke/hardware-specific.nix`
    ```diff
    -_: {
    -  hardware.bluetooth = {
    -    enable = true;
    -    powerOnBoot = true;
    -    settings = {
    -      General = {
    -        Enable = "Source,Sink,Media,Socket";
    -      };
    -    };
    -  };
    -}
    +_: {
    +  my.features.system.bluetooth.enable = true;
    +}
    ```
    *   **Datei:** `hosts/jello/hardware-specific.nix`
    ```diff
    -  hardware.bluetooth = {
    -    enable = true;
    -    settings = {
    -      General = {
    -        Enable = "Source,Sink,Media,Socket";
    -      };
    -    };
    -  };
    +  my.features.system.bluetooth.enable = true;
    ```
*   **Teststrategie:**
    1. `nix flake check`
    2. Überprüfen, ob `systemctl status bluetooth` nach dem Deployment auf Yorke/Jello aktiv ist.

---

## Schritt 3: Niri Wallpaper-Pfad in Store-Pfad umwandeln
Ersetzt den hartcodierten absoluten Systempfad `/etc/nixos/media/wallpaper.jpg` durch einen robusten relativen Flake-Pfad.

*   **Machbarkeit:** Einzeln deploybar.
*   **Zeit/Mühe:** Klein (~5 Minuten)
*   **Risiko:** Gering (Wallpaper könnte kurzzeitig schwarz sein, falls Pfad ungültig).
*   **Konkreter Code-Diff:**
    *   **Datei:** `features/desktop/niri/default.nix`
    ```diff
    -              {
    -                argv = [
    -                  "axis-shell"
    -                  "--wallpaper"
    -                  "/etc/nixos/media/wallpaper.jpg"
    -                  "--locked"
    -                ];
    -              }
    +              {
    +                argv = [
    +                  "axis-shell"
    +                  "--wallpaper"
    +                  "${../../../../media/wallpaper.jpg}"
    +                  "--locked"
    +                ];
    +              }
    ```
*   **Teststrategie:**
    1. `nix flake check`
    2. Prüfen, ob nach dem Build das Bild im Nix-Store liegt (`nix-store -q --references ...`).

---

## Schritt 4: Niri Multi-Monitor-Konfiguration entkoppeln
Entfernt die hardcodierte Abfrage `hostname == "jello"` aus dem Niri-Feature-Modul und überführt sie in eine Schnittstelle.

*   **Machbarkeit:** Einzeln deploybar.
*   **Zeit/Mühe:** Klein (~20 Minuten)
*   **Risiko:** Sehr gering.
*   **Konkreter Code-Diff:**
    *   **Datei:** `features/desktop/niri/default.nix`
    ```diff
    -  options.my.features.desktop.niri = {
    -    enable = lib.mkEnableOption "Niri desktop environment";
    -  };
    +  options.my.features.desktop.niri = {
    +    enable = lib.mkEnableOption "Niri desktop environment";
    +    outputs = lib.mkOption {
    +      type = lib.types.attrs;
    +      default = if hostname == "jello" then {
    +        "DP-1" = {
    +          position = { x = 320; y = 0; };
    +        };
    +        "HDMI-A-2" = {
    +          position = { x = 0; y = 1080; };
    +          focus-at-startup = true;
    +        };
    +      } else { };
    +      description = "Niri output configurations (positions, scales, etc.)";
    +    };
    +  };
    ```
    ```diff
    -            outputs = lib.mkIf (hostname == "jello") {
    -              "DP-1" = {
    -                position = {
    -                  x = 320;
    -                  y = 0;
    -                };
    -              };
    -              "HDMI-A-2" = {
    -                position = {
    -                  x = 0;
    -                  y = 1080;
    -                };
    -                focus-at-startup = true;
    -              };
    -            };
    +            outputs = cfg.outputs;
    ```
    *   *Optionaler Folgeschritt (zur vollständigen Bereinigung):* Verschiebung der Monitor-Config in `hosts/jello/configuration.nix` und Setzen des default-Werts im Feature auf `{}`.

*   **Teststrategie:**
    1. `nix flake check`
    2. Evaluation für Jello prüfen: `nix-instantiate --eval -A nixosConfigurations.jello.config.programs.niri.settings.outputs`

---

## Schritt 5: Authentik Outpost Proxy konfigurierbar machen
Entkoppelt die IP des Authentik-Core-Servers und die Browser-URL vom Host `mackaye`.

*   **Machbarkeit:** Einzeln deploybar.
*   **Zeit/Mühe:** Klein (~15 Minuten)
*   **Risiko:** Gering (Authentik Forward-Auth könnte fehlschlagen bei Falschkonfiguration).
*   **Konkreter Code-Diff:**
    *   **Datei:** `features/services/authentik/outpost/proxy/default.nix`
    ```diff
    -let
    -  cfg = config.my.features.services.authentik.outpost.proxy;
    -  authentikHost = config.my.features.system.networking.topology.hosts.mackaye.tailscaleIp;
    -in
    +let
    +  cfg = config.my.features.services.authentik.outpost.proxy;
    +in
     {
       options.my.features.services.authentik.outpost.proxy = {
         enable = lib.mkEnableOption "Authentik Proxy Outpost";
         tokenSecretName = lib.mkOption {
           type = lib.types.str;
           default = "authentik_outpost_proxy_token";
           description = "The name of the secret in sops containing the Authentik proxy token.";
         };
+        coreAddress = lib.mkOption {
+          type = lib.types.str;
+          default = "http://${config.my.features.system.networking.topology.hosts.mackaye.tailscaleIp}:9055";
+          description = "Internal address of the Authentik Core instance.";
+        };
+        browserUrl = lib.mkOption {
+          type = lib.types.str;
+          default = "https://auth.ancoris.ovh";
+          description = "Public browser facing URL of the Authentik Core instance.";
+        };
       };
    ```
    ```diff
         # Configure connection to Authentik Core via Tailscale
         Environment = [
-          "AUTHENTIK_HOST=http://${authentikHost}:9055"
-          "AUTHENTIK_HOST_BROWSER=https://auth.ancoris.ovh"
+          "AUTHENTIK_HOST=${cfg.coreAddress}"
+          "AUTHENTIK_HOST_BROWSER=${cfg.browserUrl}"
           "AUTHENTIK_INSECURE_SKIP_VERIFY=true"
    ```
*   **Teststrategie:**
    1. `nix flake check`
    2. Verify, dass der Proxy-Dienst startet und sich weiterhin mit Authentik-Core verbindet.

---

## Schritt 6: Robustheit von `hermes-webui` gegen fehlenden Agenten sichern
Verhindert Evaluations-Abbrüche, wenn `hermes-webui` ohne `hermes-agent` geladen wird.

*   **Machbarkeit:** Keine.
*   **Zeit/Mühe:** Klein (~10 Minuten)
*   **Risiko:** Keine.
*   **Konkreter Code-Diff:**
    *   **Datei:** `features/services/hermes-webui/default.nix`
    ```diff
    +let
    +  cfg = config.my.features.services.hermes-webui;
    +  envPath = if config.sops.secrets ? hermes_agent_env then config.sops.secrets.hermes_agent_env.path else "/dev/null";
    +in
     {
    ```
    ```diff
       config = lib.mkIf cfg.enable {
    +    assertions = [
    +      {
    +        assertion = config.my.features.services.hermes-agent.enable or false;
    +        message = "hermes-webui requires hermes-agent to be enabled on the same host.";
    +      }
    +    ];
    +
         systemd.services.hermes-webui = {
    ```
    ```diff
           preStart = ''
             ${pkgs.docker}/bin/docker pull ghcr.io/nesquena/hermes-webui:latest || true
             ${pkgs.docker}/bin/docker rm -f hermes-webui || true
             mkdir -p /run/hermes-webui
             # Filter out environment variables starting with a digit (invalid in POSIX/bash)
-            ${pkgs.gnugrep}/bin/grep -vE '^[0-9]' ${config.sops.secrets.hermes_agent_env.path} > /run/hermes-webui/env || true
+            ${pkgs.gnugrep}/bin/grep -vE '^[0-9]' ${envPath} > /run/hermes-webui/env || true
    ```
*   **Teststrategie:**
    1. `nix flake check`
    2. Aktivieren Sie temporär `hermes-webui.enable = true` auf einem Host ohne `hermes-agent`. Der Build darf nicht mit "undefined attribute" abstürzen, sondern muss mit der definierten Assertion-Meldung stoppen.

---

## Schritt 7: Hermes-Agent URLs und Chat-ID entkoppeln
Ersetzt die hartcodierten URLs von Home Assistant, Paperless und die Telegram Chat-ID durch parametrisierte Modul-Optionen.

*   **Machbarkeit:** Einzeln deploybar.
*   **Zeit/Mühe:** Mittel (~25 Minuten)
*   **Risiko:** Gering (Ausfall der Kommunikation zwischen Hermes und HASS/Paperless bei falschen Werten).
*   **Konkreter Code-Diff:**
    *   **Datei:** `features/services/hermes-agent/default.nix`
    ```diff
       options.my.features.services.hermes-agent = {
         enable = lib.mkEnableOption "Hermes Agent";
         model = lib.mkOption {
           type = lib.types.str;
           default = "deepseek-v4-pro";
           description = "Default model for Hermes Agent.";
         };
         hostUsers = lib.mkOption {
           type = lib.types.listOf lib.types.str;
           default = [ ];
           description = "Interactive host users who should have access to the hermes group.";
         };
         subdomainDelegation = lib.mkOption {
           type = lib.types.bool;
           default = false;
           description = "Enable subdomain delegation (*.moebius → Hermes container Caddy)";
         };
+        hassUrl = lib.mkOption {
+          type = lib.types.str;
+          default = if config.my.endpoints ? home-assistant && config.my.endpoints.home-assistant.subdomain != null
+                    then "https://${config.my.endpoints.home-assistant.subdomain}.${config.my.features.services.caddy.baseDomain or "fls.ancoris.ovh"}"
+                    else "https://hass.fls.ancoris.ovh";
+          description = "Home Assistant URL connection endpoint.";
+        };
+        paperlessUrl = lib.mkOption {
+          type = lib.types.str;
+          default = if config.my.endpoints ? paperless && config.my.endpoints.paperless.subdomain != null
+                    then "https://${config.my.endpoints.paperless.subdomain}.${config.my.features.services.caddy.baseDomain or "fls.ancoris.ovh"}"
+                    else "https://paperless.fls.ancoris.ovh";
+          description = "Paperless connection endpoint.";
+        };
+        telegramChatId = lib.mkOption {
+          type = lib.types.str;
+          default = "5838211825";
+          description = "Telegram Chat ID to inject into legacy config updates.";
+        };
       };
    ```
    ```diff
       config = lib.mkIf cfg.enable {
         services.hermes-agent = {
           enable = true;
           ...
           environment = {
             MNEMOSYNE_EMBEDDING_MODEL = "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2";
-            HASS_URL = "https://hass.fls.ancoris.ovh";
-            PAPERLESS_URL = "https://paperless.fls.ancoris.ovh";
+            HASS_URL = cfg.hassUrl;
+            PAPERLESS_URL = cfg.paperlessUrl;
             CAMOFOX_URL = "http://127.0.0.1:9377";
           };
    ```
    ```diff
           # Fix permissions and migrate config after upstream activation
           system.activationScripts."hermes-agent-fix-perms" = lib.stringAfter [ "hermes-agent-setup" ] ''
             # TODO: remove when upstream hermes-agent handles legacy string home_channel format
             ${pkgs.python3.withPackages (ps: [ ps.pyyaml ])}/bin/python3 << 'PYEOF'
             import yaml
             path = "/var/lib/hermes/.hermes/config.yaml"
             try:
                 with open(path) as f:
                     cfg = yaml.safe_load(f)
             except Exception:
                 raise SystemExit(0)
             changed = False
-            nc = {"platform": "telegram", "chat_id": "5838211825"}
+            nc = {"platform": "telegram", "chat_id": "${cfg.telegramChatId}"}
    ```
*   **Teststrategie:**
    1. `nix flake check`
    2. Evaluation prüfen: `nix-instantiate --eval -A nixosConfigurations.rollins.config.services.hermes-agent.environment`

---

## Schritt 8: Rollen-Refactoring (`base.nix` einführen)
Eliminiert die redundanten Standardeinstellungen in `roles/pc.nix` und `roles/server.nix`.

*   **Machbarkeit:** Dieser Schritt benötigt zwingend Schritt 1 (Safe-Guard im Helper), da bei Rebuilds die Module neu sortiert ausgewertet werden.
*   **Zeit/Mühe:** Mittel (~30 Minuten)
*   **Risiko:** Mittel (Konfigurationsfehler, falls Defaults überschrieben werden).
*   **Konkreter Code-Diff:**
    *   **Neue Datei:** `roles/base.nix`
    ```nix
    { lib, ... }:
    {
      my.features = {
        system = {
          common.enable = lib.mkDefault true;
          bootloader = {
            enable = lib.mkDefault true;
            provider = lib.mkDefault "systemd-boot";
          };
          kernel.enable = lib.mkDefault true;
          fish-shell.enable = lib.mkDefault true;
          networking.topology.enable = lib.mkDefault true;
        };
      };

      my.features.system.networking.ssh.enable = lib.mkDefault true;
    }
    ```
    *   **Datei:** `roles/server.nix`
    ```diff
    - { lib, ... }:
    -
    - {
    -   my.role = "server";
    -
    -   my.features = {
    -     system = {
    -       common.enable = lib.mkDefault true;
    -       bootloader = {
    -         enable = lib.mkDefault true;
    -         provider = lib.mkDefault "systemd-boot";
    -       };
    -       kernel.enable = lib.mkDefault true;
    -       fish-shell.enable = lib.mkDefault true;
    -       networking.topology.enable = lib.mkDefault true;
    -     };
    -   };
    -
    -   my.features.system.networking.ssh.enable = lib.mkDefault true;
    - }
    + { ... }:
    + {
    +   imports = [ ./base.nix ];
    +   my.role = "server";
    + }
    ```
    *   **Datei:** `roles/pc.nix`
    ```diff
     {
       lib,
       inputs,
       pkgs,
       ...
     }:
    -
     {
    +  imports = [ ./base.nix ];
    +
       hardware.enableRedistributableFirmware = lib.mkDefault true;
    -  # It enables a baseline set of features common to all graphical systems.
    -  my.features = {
    -    system = {
    -      common.enable = lib.mkDefault true;
    -      audio.enable = lib.mkDefault true;
    -      bootloader = {
    -        enable = lib.mkDefault true;
    -        provider = lib.mkDefault "systemd-boot";
    -      };
    -      kernel.enable = lib.mkDefault true;
    -      wayland.enable = lib.mkDefault true;
    -      fish-shell.enable = lib.mkDefault true;
    -      printing.enable = lib.mkDefault true;
    -      networking.topology.enable = lib.mkDefault true;
    -    };
    -  };
    +  my.features.system.audio.enable = lib.mkDefault true;
    +  my.features.system.wayland.enable = lib.mkDefault true;
    +  my.features.system.printing.enable = lib.mkDefault true;
    
       services.xserver.xkb.layout = lib.mkDefault "de";
       ...
    ```
*   **Teststrategie:**
    1. `nix flake check`
    2. Vergleichende Evaluation: Führe vor und nach dem Refactoring `nix-instantiate --eval -A nixosConfigurations.yorke.config.my.features` aus und vergleiche die Ergebnisse (müssen absolut identisch sein).

---

## Schritt 9: Statische IP-Konfiguration (Server) in Feature modularisieren
Beseitigt die IP-Konfigurations-Duplizierung in `mackaye/configuration.nix` und `rollins/configuration.nix`.

*   **Machbarkeit:** Einzeln deploybar.
*   **Zeit/Mühe:** Mittel (~25 Minuten)
*   **Risiko:** Mittel (Verlust der Netzwerkverbindung auf Mackaye/Rollins, falls die statischen IPs falsch zugewiesen werden).
*   **Konkreter Code-Diff:**
    *   **Neue Datei:** `features/system/networking/static/default.nix`
    ```nix
    { config, lib, ... }:
    let
      cfg = config.my.features.system.networking.static;
      hostName = config.networking.hostName;
      topology = config.my.features.system.networking.topology;
      hostTopology = topology.hosts.${hostName} or null;
    in
    {
      options.my.features.system.networking.static = {
        enable = lib.mkEnableOption "Static IP setup based on topology";
      };

      config = lib.mkIf (cfg.enable && hostTopology != null && hostTopology.localIp != null && hostTopology.gateway != null) {
        networking.useDHCP = false;
        networking.interfaces.eth0.useDHCP = false;
        networking.defaultGateway = hostTopology.gateway;
        networking.nameservers = [
          "9.9.9.9"
          "1.1.1.1"
        ];
        networking.interfaces.eth0.ipv4.addresses = [
          {
            address = hostTopology.localIp;
            prefixLength = 24;
          }
        ];
      };
    }
    ```
    *   **Datei:** `hosts/mackaye/configuration.nix`
    ```diff
    -  networking.useDHCP = false;
    -  networking.interfaces.eth0.useDHCP = false;
    -  networking.defaultGateway = hostTopology.gateway;
    -  networking.nameservers = [
    -    "9.9.9.9"
    -    "1.1.1.1"
    -  ];
    -  networking.interfaces.eth0.ipv4.addresses = [
    -    {
    -      address = hostTopology.localIp;
    -      prefixLength = 24;
    -    }
    -  ];
    +  my.features.system.networking.static.enable = true;
    ```
    *   **Datei:** `hosts/rollins/configuration.nix` (analog zu mackaye editieren).

*   **Teststrategie:**
    1. `nix flake check`
    2. Validierung der Netzwerk-Konfiguration vor dem Reboot auf dem Server.

---

## Schritt 10: SABnzbd Usenet-Konfiguration & Pfade entkoppeln
Führt Optionen für Verzeichnisse und Serverdaten ein, um das SABnzbd-System-Feature frei von persönlichen Benutzer-Daten zu machen.

*   **Machbarkeit:** Einzeln deploybar.
*   **Zeit/Mühe:** Mittel (~30 Minuten)
*   **Risiko:** Gering (SABnzbd kann bei falschen Pfad-Berechtigungen nicht schreiben).
*   **Konkreter Code-Diff:**
    *   **Datei:** `features/services/sabnzbd/default.nix`
    ```diff
     {
       config,
       lib,
       ...
     }:
     let
       cfg = config.my.features.services.sabnzbd;
     in
     {
       options.my.features.services.sabnzbd = {
         enable = lib.mkEnableOption "SABnzbd Usenet Downloader";
+        downloadDir = lib.mkOption {
+          type = lib.types.str;
+          default = "/data/storage/downloads";
+          description = "Path to download directory.";
+        };
+        server = {
+          enable = lib.mkOption {
+            type = lib.types.bool;
+            default = true;
+          };
+          name = lib.mkOption {
+            type = lib.types.str;
+            default = "Newsgroup Ninja";
+          };
+          host = lib.mkOption {
+            type = lib.types.str;
+            default = "news.newsgroup.ninja";
+          };
+          port = lib.mkOption {
+            type = lib.types.int;
+            default = 563;
+          };
+          ssl = lib.mkOption {
+            type = lib.types.bool;
+            default = true;
+          };
+          connections = lib.mkOption {
+            type = lib.types.int;
+            default = 50;
+          };
+          username = lib.mkOption {
+            type = lib.types.str;
+            default = "Butchey";
+          };
+        };
       };
    ```
    ```diff
         # 3. SABnzbd Service
         services.sabnzbd = {
           enable = true;
           user = "sabnzbd";
           group = "media";
           allowConfigWrite = false;
           configFile = null;
           secretFiles = [ config.sops.templates."sabnzbd-secret.ini".path ];
     
           settings = {
             misc = {
               port = 8080;
               host = "0.0.0.0";
               host_whitelist = "${
                 if config.my.endpoints.sabnzbd.subdomain != null then
                   "${config.my.endpoints.sabnzbd.subdomain}.${config.my.features.services.caddy.baseDomain}, "
                 else
                   ""
               }localhost, 127.0.0.1";
               inet_exposure = 4;
-              download_dir = "/data/storage/downloads/incomplete";
-              complete_dir = "/data/storage/downloads/complete";
+              download_dir = "${cfg.downloadDir}/incomplete";
+              complete_dir = "${cfg.downloadDir}/complete";
               permissions = "775";
               cache_limit = "512M";
               bandwidth_max = "12.5M";
               bandwidth_perc = 90;
             };
-            servers.ninja = {
-              name = "Newsgroup Ninja";
-              displayname = "Newsgroup Ninja";
-              host = "news.newsgroup.ninja";
-              port = 563;
-              ssl = true;
-              connections = 50;
-              username = "Butchey";
-              enable = true;
-            };
+            servers = lib.mkIf cfg.server.enable {
+              ninja = {
+                inherit (cfg.server) name host port ssl connections username;
+                displayname = cfg.server.name;
+                enable = true;
+              };
+            };
             categories = {
               movies = {
                 name = "movies";
                 order = 0;
               };
               tv = {
                 name = "tv";
                 order = 0;
               };
             };
           };
         };
     
         # Hoheit über den Download-Ordner
         users.groups.media = { };
         users.users.sabnzbd.extraGroups = [ "media" ];
     
         systemd.tmpfiles.rules = [
-          "d /data/storage/downloads 0775 sabnzbd media -"
-          "d /data/storage/downloads/incomplete 0775 sabnzbd media -"
-          "d /data/storage/downloads/complete 0775 sabnzbd media -"
+          "d ${cfg.downloadDir} 0775 sabnzbd media -"
+          "d ${cfg.downloadDir}/incomplete 0775 sabnzbd media -"
+          "d ${cfg.downloadDir}/complete 0775 sabnzbd media -"
         ];
     
         systemd.services.sabnzbd.serviceConfig = {
-          ReadWritePaths = [ "/data/storage/downloads" ];
+          ReadWritePaths = [ cfg.downloadDir ];
           UMask = lib.mkForce "0002";
         };
    ```
*   **Teststrategie:**
    1. `nix flake check`
    2. Überprüfen, ob SABnzbd nach dem Deployment auf `strummer` fehlerfrei startet und weiterhin Zugriff auf `/data/storage/downloads` hat.
