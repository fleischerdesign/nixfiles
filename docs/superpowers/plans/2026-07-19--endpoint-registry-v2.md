# Endpoint Registry v2 — Implementation Plan
> **Goal:** Migrate `my.endpoints` from flat Caddy schema to grouped `proxy`/`directAccess` model, add firewall auto-config.

**Architecture:** Two new submodules (`proxy`, `directAccess`) in the endpoint schema. Caddy reads `proxy.*`. New `firewall.nix` reads `directAccess.*`. All old flat fields removed — no aliases, no compat layer.

**Tech Stack:** Nix, nixfmt, deadnix, statix

---

### Task 1: Schema (endpoints/default.nix)
**Files:** `features/endpoints/default.nix`

- [ ] Add `proxy` submodule with `enable` (default `false`), `subdomain`, `websocket`, `auth`
- [ ] Add `directAccess` submodule with `enable` (default `false`)
- [ ] Remove top-level `subdomain`, `auth`, `caddy` options
- [ ] Keep `host`, `port`, `fullDomain`, `monitoring` unchanged
- [ ] Run `nix-instantiate --eval` to verify schema parses

---

### Task 2: Consumer — Caddy
**Files:** `features/services/caddy/default.nix`

- [ ] Replace `ep.caddy.enable` → `ep.proxy.enable`
- [ ] Replace `ep.subdomain` → `ep.proxy.subdomain`
- [ ] Replace `ep.auth` → `ep.proxy.auth`
- [ ] Add `ep.proxy.websocket` support (if websocket → pass through)

---

### Task 3: Migrate host endpoint definitions
**Files:** `hosts/rollins/configuration.nix`, `hosts/strummer/configuration.nix`

rollins:
- [ ] `auth = false` → `proxy.auth = false`
- [ ] `subdomain = "moebius"` → `proxy.subdomain = "moebius"`
- [ ] Add `proxy.enable = true` where subdomain was set

strummer (14 endpoints):
- [ ] Every `subdomain = "X"` → `proxy = { enable = true; subdomain = "X"; }`
- [ ] Every `auth = true` → merged into the `proxy` block
- [ ] Entries that only have `host`/`port` stay as-is (no proxy needed)

---

### Task 4: Migrate feature endpoint references
**Files:** Multiple

- [ ] `klipper/default.nix`: `caddy.enable = false` → `proxy.enable = false`
- [ ] `paperless/default.nix`, `mealie/default.nix`, `sabnzbd/default.nix`, `ntfy/default.nix`, `hermes-agent/default.nix`: `config.my.endpoints.X.subdomain` → `config.my.endpoints.X.proxy.subdomain`
- [ ] `hermes-webui/default.nix`: `ep.subdomain` → `ep.proxy.subdomain`

---

### Task 5: Add firewall auto-config
**Files:** NEW `features/system/common/firewall.nix`

- [ ] Create module that reads `config.my.endpoints` 
- [ ] Opens `allowedTCPPorts` for endpoints on this host with `directAccess.enable = true`
- [ ] Home Assistant: add `directAccess.enable = true` to its endpoint
- [ ] Klipper: add `directAccess.enable = true` to its endpoint
- [ ] Remove `networking.firewall.allowedTCPPorts` from HA and Klipper feature files

---

### Task 6: Verify, format, lint
- [ ] `nix develop -c nixfmt` on all changed files
- [ ] `nix develop -c deadnix --fail` on all changed files
- [ ] `nix develop -c statix check`
- [ ] Manual review: every endpoint with `proxy.enable = true` must have `proxy.subdomain` or `fullDomain` set
- [ ] Manual review: no port silently opened or closed

---

### Task 7: Commit and push
- [ ] Review diff for correctness
- [ ] Commit with detailed message
- [ ] Push
