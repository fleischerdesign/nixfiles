# VYRX Design System & Visual Identity Specification

> **Status:** Specification & Implementation Guide  
> **Aesthetic:** Modern Industrial Minimalist / High-End Developer Tooling (Linear / Vercel / Raycast style)  
> **Scope:** Authentik SSO Gateway, Caddy Error Pages, Internal Dashboards & Web Services  
> **Domain:** `vyrx.de`

---

## 1. Leitphilosophie & Design-Prinzipien

Das **VYRX Design System** definiert eine ruhige, hochmoderne und funktionale Benutzeroberfläche für alle Dienste unter `vyrx.de`. Der Fokus liegt auf kompromissloser typografischer Präzision, reduzierter visueller Hierarchie und erstklassiger Usability – ohne verspielte Sci-Fi-Tropen, pseudotechnische Deko-Header oder visuelles Rauschen.

### Kernprinzipien:
1. **Funktionaler Minimalismus:** Jedes visuelle Element hat eine Aufgabe. Klare Kontraste, ruhige Flächen und durchdachte Weißräume (bzw. Dunkelräume).
2. **Präzise typografische Skala:** Primär moderne Sans-Serif-Typografie (`Geist Sans` oder `Inter`) für Formulare und Navigation. Monospace (`Geist Mono`, `JetBrains Mono`) ausschließlich für reale technische Daten (IPs, Ports, Hashes, Latenzen).
3. **Subtile Tiefe & Kantenkontrast:** Neutrale Zink-/Schiefer-Farbtöne mit präzisen `1px`-Bordern (`rgba(255, 255, 255, 0.08)`). Keine übertriebenen Neon-Effekte, sondern feine, matte Weichzeichner.
4. **Passkey-First UX:** Biometrische Authentifizierung (FIDO2 / WebAuthn) steht als primärer Interaktionspfad im Zentrum. Schnörkellos und schnell.
5. **Ernsthafte Fehler-Diagnostik:** Status- und Fehlerseiten liefern dem Administrator echte, strukturierte Diagnosedaten nach Vorbild moderner Cloud-Plattformen (Cloudflare, Vercel), statt generischer Fehlerboxen.

---

## 2. Design Tokens (Farbsystem & CSS-Variablen)

Das Farbsystem basiert auf neutralen Grau- und Schwarzwerten mit einem dezenten, hochwertigen Akzentton.

```css
:root {
  /* Surface Layers (Neutrals / Dark Mode) */
  --vyrx-bg-canvas:      #09090B; /* Canvas base (Zinc 950) */
  --vyrx-bg-card:        #121215; /* Card container */
  --vyrx-bg-elevated:    #18181B; /* Inputs, Dropdowns, Controls (Zinc 900) */
  --vyrx-bg-hover:       #27272A; /* Control Hover (Zinc 800) */

  /* Borders & Dividers */
  --vyrx-border-subtle:  rgba(255, 255, 255, 0.08);
  --vyrx-border-default: rgba(255, 255, 255, 0.12);
  --vyrx-border-strong:  rgba(255, 255, 255, 0.20);
  --vyrx-border-focus:   #6366F1; /* Indigo 500 */

  /* Semantic Accents */
  --vyrx-accent-primary: #6366F1; /* Primary brand & focus */
  --vyrx-accent-success: #10B981; /* Verified / Passkey OK (Emerald 500) */
  --vyrx-accent-warning: #F59E0B; /* Pending / Warning (Amber 500) */
  --vyrx-accent-danger:  #EF4444; /* Error / Denied (Red 500) */

  /* Typography Colors */
  --vyrx-text-primary:   #F8FAFC; /* Slate 50 */
  --vyrx-text-secondary: #94A3B8; /* Slate 400 */
  --vyrx-text-muted:     #64748B; /* Slate 500 */

  /* Focus & Shadows */
  --vyrx-shadow-card:    0 12px 32px -4px rgba(0, 0, 0, 0.5), 0 0 0 1px var(--vyrx-border-subtle);
  --vyrx-shadow-focus:   0 0 0 2px var(--vyrx-bg-canvas), 0 0 0 4px var(--vyrx-accent-primary);

  /* Geometry */
  --vyrx-radius-sm:      6px;
  --vyrx-radius-md:      8px;
  --vyrx-radius-lg:      12px;
}
```

---

## 3. Typografie

* **UI & Body:** `Geist Sans`, `Inter`, `-apple-system`, `BlinkMacSystemFont`, `sans-serif`
  * Saubere Glyphen, hervorragende Lesbarkeit auf hochauflösenden Displays, neutraler Charakter.
* **Code & Telemetrie:** `Geist Mono`, `JetBrains Mono`, `ui-monospace`, `monospace`
  * Ausschließlich für maschinenlesbare Parameter (IP-Adressen, Ports, Timestamps, Request-IDs).

---

## 4. Authentik SSO Loginmaske (`auth.vyrx.de`)

Die Authentik-Oberfläche wird auf ein aufgeräumtes, elegantes Interface reduziert.

### 4.1 Layout & Komponenten
* **Hintergrund:** Ruhiges `--vyrx-bg-canvas` (`#09090B`) mit minimalem radialen Lichtakzent im oberen Drittel.
* **Card-Container:**
  * Maximalbreite 400px, zentriert.
  * Hintergrund `--vyrx-bg-card` (`#121215`), dezente Kante (`1px solid var(--vyrx-border-subtle)`), feiner Schlagschatten.
* **Header:**
  * Minimalistisches VYRX-Wortmarken-Logo (schlichte Grotesk-Typografie, Tracking `-0.04em`).
  * Subtiler Subtitle: `Sign in to access your services`.
* **Passkey / WebAuthn Button:**
  * Primäre Schaltfläche: Helles Weiß (`#F8FAFC`) auf dunklem Grund oder diskret gefüllt mit `--vyrx-accent-primary`.
  * Klares Icon (FIDO2 / Biometrie-Symbol), präziser Text: `Sign in with Passkey`.
* **Formular-Felder:**
  * Dunkle, leicht abgesetzte Inputs (`--vyrx-bg-elevated`).
  * Border `1px solid var(--vyrx-border-default)`, bei Focus saubere Kante ohne Farbexplosionen.

### 4.2 Authentik Custom CSS Blueprint:
```css
/* vyrx-authentik-clean.css */
@import url('https://fonts.googleapis.com/css2?family=Geist:wght@400;500;600&family=Geist+Mono:wght@400;500&display=swap');

body {
  background-color: #09090B !important;
  background-image: radial-gradient(circle at 50% 10%, rgba(99, 102, 241, 0.08) 0%, transparent 45%) !important;
  color: #F8FAFC !important;
  font-family: 'Geist', -apple-system, sans-serif !important;
  -webkit-font-smoothing: antialiased;
}

/* Container */
.pf-c-login__container {
  background: #121215 !important;
  border: 1px solid rgba(255, 255, 255, 0.08) !important;
  border-radius: 12px !important;
  box-shadow: 0 12px 32px -4px rgba(0, 0, 0, 0.5) !important;
  padding: 2.25rem !important;
  max-width: 420px !important;
  width: 100% !important;
}

/* Header & Brand */
.pf-c-brand {
  margin-bottom: 1.25rem !important;
}

.pf-c-title {
  color: #F8FAFC !important;
  font-weight: 600 !important;
  font-size: 1.25rem !important;
  letter-spacing: -0.02em !important;
}

/* Form Controls */
.pf-c-form-control {
  background-color: #18181B !important;
  border: 1px solid rgba(255, 255, 255, 0.12) !important;
  border-radius: 8px !important;
  color: #F8FAFC !important;
  font-size: 0.9rem !important;
  padding: 0.6rem 0.85rem !important;
  transition: border-color 0.15s ease, box-shadow 0.15s ease !important;
}

.pf-c-form-control:focus {
  border-color: #6366F1 !important;
  box-shadow: 0 0 0 2px #09090B, 0 0 0 4px rgba(99, 102, 241, 0.35) !important;
  outline: none !important;
}

/* Primary Button (Passkey / Sign In) */
.pf-c-button.pf-m-primary {
  background-color: #F8FAFC !important;
  color: #09090B !important;
  border: none !important;
  border-radius: 8px !important;
  font-weight: 500 !important;
  font-size: 0.9rem !important;
  padding: 0.65rem 1rem !important;
  transition: opacity 0.15s ease, transform 0.15s ease !important;
}

.pf-c-button.pf-m-primary:hover {
  opacity: 0.92 !important;
}

.pf-c-button.pf-m-primary:active {
  transform: scale(0.98);
}
```

---

## 5. Caddy Ingress Status- & Fehlerseiten

Tritt beim Routing ein Fehler auf (z. B. 502 Bad Gateway oder 403 Forbidden), zeigt Caddy eine professionelle, klare Diagnoseseite nach dem Vorbild von Cloudflare- oder Vercel-Statusanzeigen:

```
+-----------------------------------------------------------------------+
|  vyrx                                                   Status: Error |
+-----------------------------------------------------------------------+
|                                                                       |
|  502                                                                  |
|  Upstream Service Unavailable                                         |
|                                                                       |
|  The gateway was unable to reach the configured upstream host.        |
|                                                                       |
|  ───────────────────────────────────────────────────────────────────  |
|                                                                       |
|  Diagnostic Information                                               |
|  Target Service:     jellyfin.vyrx.de                                 |
|  Upstream Host:      hom-srv-01.node.vyrx.de:8096                     |
|  Gateway Node:       cld-edge-01 (WireGuard Mesh)                     |
|  Timestamp:          2026-09-17T18:30:00Z                             |
|  Ray ID / Trace:     req_01j8m4n2k9                                   |
|                                                                       |
|  ───────────────────────────────────────────────────────────────────  |
|                                                                       |
|  [ Try Again ]                                 [ Cluster Status ]     |
+-----------------------------------------------------------------------+
```

### Struktur:
* **Keine reißerischen Alarmtexte:** Ruhige, eindeutige Fehlerbezeichnung (`502 Upstream Service Unavailable`).
* **Kompakte Diagnosetabelle:** Zeigt Ziel-Service, Ziel-Host, Gateway und Request-ID in sauberer Monospace-Darstellung.
* **Ergonomische Aktionen:** Ein klarer Retry-Button und ein Link zum internen Status-Dashboard.

---

## 6. Status-Indikatoren & Badges

Diskrete Statusanzeigen für interne Dashboards und Service-Listen:

| Zustand | Indikator | Farbe | Bedeutung |
|---|---|---|---|
| **Operational** | Grüner Punkt (`8px`) | `#10B981` | Dienst erreichbar, Health Check 200 OK |
| **Degraded** | Gelber Punkt (`8px`) | `#F59E0B` | Antwortzeit > 1500ms oder Warnungen |
| **Down** | Roter Punkt (`8px`) | `#EF4444` | Dienst nicht erreichbar |
| **Internal Only** | Monospace Badge | `text-slate-400, bg-zinc-900` | Nur im Mesh/LAN (`*.lan.vyrx.de`) |

---

## 7. Deklarative Bereitstellung in NixOS (`features/system/theme`)

Das Theme wird als eigenständiges, agnostisches Feature-Modul in NixOS eingebunden:

1. **Dateistruktur:**
   ```
   features/system/theme/
   ├── default.nix               # NixOS Options & tmpfiles-Wiring
   └── assets/
       ├── authentik.css         # Bereinigtes Authentik CSS
       ├── error-502.html        # Caddy Error-Template
       └── logo.svg              # Minimales VYRX Vektorlogo
   ```

2. **Caddy Integration:**
   ```caddy
   (vyrx_errors) {
     handle_errors {
       rewrite * /errors/{err.status_code}.html
       file_server {
         root /etc/vyrx/theme
       }
     }
   }
   ```

3. **Authentik Integration:**
   ```nix
   systemd.tmpfiles.rules = [
     "L+ /var/lib/authentik/theme.css - - - - ${./assets/authentik.css}"
   ];
   ```

---

## 8. Zusammenfassung

Das bereinigte **VYRX Design System** setzt auf **zeitloses, professionelles Industrie-Design**. Es verzichtet vollständig auf Gimmicks und liefert stattdessen eine ergonomische, konsistente und hochgradig saubere Oberfläche für Admins und Nutzer.
