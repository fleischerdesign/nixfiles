# Design system

> **Aesthetic:** modern industrial minimalist - the register of high-end developer tooling
> **Scope:** the Authentik portal, Caddy's error pages, internal dashboards
> **Naming:** see [naming.md](naming.md) - normative, derived, never maintained by hand.

## 1. Principles

The design system defines a calm, functional surface for every service under `vyrx.de`: typographic
precision, a reduced hierarchy, and no decoration for its own sake - no sci-fi tropes, no
pseudo-technical ornament.

1. **Functional minimalism.** Every visual element has a job. Clear contrast, quiet surfaces,
   deliberate space.
2. **One type scale.** Modern sans-serif (`Geist Sans`, `Inter`) for forms and navigation. Monospace
   (`Geist Mono`, `JetBrains Mono`) only for machine-readable values: addresses, ports, hashes,
   latencies. Using monospace for prose would defeat the distinction it exists to make.
3. **Subtle depth, honest edges.** Neutral zinc and slate tones, precise `1px` borders
   (`rgba(255, 255, 255, 0.08)`), matte shadows. No neon.
4. **Passkey first.** Biometric authentication is the primary path, not an alternative standing next to
   a password field.
5. **Errors worth reading.** Status and error pages carry the structured diagnostics that modern cloud
   platforms show - what failed, what it was reaching for, which node tried - instead of a generic box.

## 2. Tokens

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

## 3. Typography

| | Stack | Used for |
|---|---|---|
| UI and body | `Geist Sans`, `Inter`, `-apple-system`, `BlinkMacSystemFont`, `sans-serif` | forms, navigation, prose |
| Code and telemetry | `Geist Mono`, `JetBrains Mono`, `ui-monospace`, `monospace` | addresses, ports, timestamps, request IDs |

## 4. The Authentik portal (`auth.vyrx.de`)

- **Background.** `--vyrx-bg-canvas` with a single restrained radial highlight in the upper third.
- **Card.** Centred, `--vyrx-bg-card`, a `1px solid var(--vyrx-border-subtle)` edge and a soft shadow.
- **Header.** The VYRX word mark in plain grotesque, tracking `-0.04em`, with the subtitle
  `Sign in to access your services`.
- **Passkey button.** White on dark, or a discreet fill with `--vyrx-accent-primary`. One clear icon and
  one precise label: `Sign in with Passkey`.
- **Form fields.** `--vyrx-bg-elevated` with `1px solid var(--vyrx-border-default)`, and a focus state
  that changes the border and adds a ring - no colour explosion.

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

## 5. Caddy error pages

When routing fails, the page says what happened and what it was trying to reach - the calm version of a
diagnostic, not an alarm:

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

- **No shouting.** A plain, unambiguous label: `502 Upstream Service Unavailable`.
- **A compact table.** Target service, target host, gateway and request ID in monospace.
- **Two actions.** Retry, and a link to the cluster status.

## 6. Status indicators

| State | Indicator | Colour | Meaning |
|---|---|---|---|
| **Operational** | green dot, `8px` | `#10B981` | reachable, health check 200 |
| **Degraded** | amber dot, `8px` | `#F59E0B` | response above 1500 ms, or warnings |
| **Down** | red dot, `8px` | `#EF4444` | does not answer |
| **Internal only** | monospace badge | `text-slate-400`, `bg-zinc-900` | reachable only from the mesh or the LAN |

## 7. Where the theme lives

A self-contained feature module, so a service does not have to know that a design exists:

```
features/system/theme/
├── default.nix               # options and tmpfiles wiring
└── assets/
    ├── authentik.css         # the Authentik stylesheet above
    ├── error-502.html        # the Caddy error template
    └── logo.svg              # the VYRX mark
```

Caddy picks the error template up as a snippet:

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

and Authentik receives the stylesheet at the path it loads it from:

```nix
systemd.tmpfiles.rules = [
  "L+ /var/lib/authentik/theme.css - - - - ${./assets/authentik.css}"
];
```

## 8. Why it looks like this

The theme is deliberately timeless: industrial, quiet, consistent. Everything here exists to make an
administrator's screen readable at a glance - which is the only design requirement a fleet's internal
surface actually has.
